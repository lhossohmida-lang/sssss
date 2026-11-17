import {
  directoryConfig,
  needsDirectoryEntry,
  phoneOfLoginEmail,
  registerStaffPhone,
  unregisterStaffPhone,
} from "./directory.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const NAMES = ["DIRECTORY_URL", "DIRECTORY_ANON_KEY", "DIRECTORY_SLUG", "DIRECTORY_REGISTER_KEY"];

function clearEnv(): void {
  for (const name of NAMES) Deno.env.delete(name);
}

Deno.test("phoneOfLoginEmail reads the phone from a generated login only", () => {
  assert(phoneOfLoginEmail("0550123456@school.local") === "0550123456", "mobile");
  assert(phoneOfLoginEmail(" 0661234567@SCHOOL.local ") === "0661234567", "trimmed and case-insensitive");
  for (
    const bad of [
      "owner@school.com",
      "0150123456@school.local",
      "055012345@school.local",
      "abc@school.local",
      "0550123456@other.local",
      "",
    ]
  ) {
    assert(phoneOfLoginEmail(bad) === null, bad);
  }
});

Deno.test("only owners and workers need a directory entry", () => {
  assert(needsDirectoryEntry("owner") && needsDirectoryEntry("worker"), "staff");
  assert(!needsDirectoryEntry("teacher") && !needsDirectoryEntry("parent"), "teachers and parents pick the school");
  assert(!needsDirectoryEntry("admin"), "unknown role");
});

Deno.test("directoryConfig needs all four secrets and trims a trailing slash", () => {
  clearEnv();
  try {
    assert(directoryConfig() === null, "nothing set");
    Deno.env.set("DIRECTORY_URL", "https://dir.supabase.co/");
    Deno.env.set("DIRECTORY_ANON_KEY", "sb_publishable_dir");
    Deno.env.set("DIRECTORY_SLUG", "alnour");
    assert(directoryConfig() === null, "the registration key is missing");
    Deno.env.set("DIRECTORY_REGISTER_KEY", "k".repeat(64));
    const config = directoryConfig();
    assert(
      config !== null && config.url === "https://dir.supabase.co" && config.slug === "alnour" &&
        config.anonKey === "sb_publishable_dir" && config.registerKey === "k".repeat(64),
      JSON.stringify(config),
    );
  } finally {
    clearEnv();
  }
});

type Seen = { url: string; body: Record<string, unknown>; headers: Headers };

function stubFetch(answer: () => Response | Promise<Response>, seen: Seen[]): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    seen.push({
      url: String(input),
      body: JSON.parse(String(init?.body)),
      headers: new Headers(init?.headers),
    });
    return Promise.resolve(answer());
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

const CONFIG = {
  url: "https://dir.supabase.co",
  anonKey: "sb_publishable_dir",
  slug: "alnour",
  registerKey: "k".repeat(64),
};

Deno.test("register and unregister call the school's own RPCs with its key", async () => {
  const seen: Seen[] = [];
  const restore = stubFetch(() => Response.json(true), seen);
  try {
    assert((await registerStaffPhone(CONFIG, "0550123456")) === true, "register");
    assert((await unregisterStaffPhone(CONFIG, "0550123456")) === true, "unregister");
  } finally {
    restore();
  }
  assert(seen.length === 2, String(seen.length));
  assert(seen[0].url === "https://dir.supabase.co/rest/v1/rpc/school_register_phone", seen[0].url);
  assert(seen[1].url === "https://dir.supabase.co/rest/v1/rpc/school_unregister_phone", seen[1].url);
  for (const call of seen) {
    assert(
      call.body.p_slug === "alnour" && call.body.p_register_key === "k".repeat(64) &&
        call.body.p_phone === "0550123456",
      JSON.stringify(call.body),
    );
    assert(call.headers.get("apikey") === "sb_publishable_dir", "the public key is sent in apikey");
    assert(call.headers.get("authorization") === null, "a non-JWT key is not sent as a bearer token");
  }
});

Deno.test("a legacy JWT anon key goes in both headers", async () => {
  const seen: Seen[] = [];
  const restore = stubFetch(() => Response.json(true), seen);
  try {
    await registerStaffPhone({ ...CONFIG, anonKey: "eyJhbGciOiJIUzI1NiJ9.e30.sig" }, "0550123456");
  } finally {
    restore();
  }
  assert(seen[0].headers.get("authorization") === "Bearer eyJhbGciOiJIUzI1NiJ9.e30.sig", "bearer");
});

Deno.test("a refusal, a non-true answer or a network failure is false and never throws", async () => {
  const seen: Seen[] = [];
  for (
    const answer of [
      () => new Response("denied", { status: 403 }),
      () => Response.json(false),
      () => Response.json({ not: "a boolean" }),
      () => new Response("not json", { status: 200 }),
    ]
  ) {
    const restore = stubFetch(answer, seen);
    try {
      assert((await registerStaffPhone(CONFIG, "0550123456")) === false, "refused");
    } finally {
      restore();
    }
  }
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new TypeError("offline"))) as typeof fetch;
  try {
    assert((await unregisterStaffPhone(CONFIG, "0550123456")) === false, "network failure");
  } finally {
    globalThis.fetch = original;
  }
});

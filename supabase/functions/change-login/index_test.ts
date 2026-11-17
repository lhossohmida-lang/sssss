import { handle } from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const OLD_EMAIL = "0550123456@school.local";
const NEW_EMAIL = "0661234567@school.local";
const OLD_PASSWORD = "Old-Sentinel-Pass-1";
const DIRECTORY_NAMES = ["DIRECTORY_URL", "DIRECTORY_ANON_KEY", "DIRECTORY_SLUG", "DIRECTORY_REGISTER_KEY"];

type Seen = {
  puts: { email: unknown; confirm: unknown; apikey: string | null }[];
  checks: { email: unknown; password: unknown }[];
  directory: { fn: string; phone: unknown }[];
};

function configure(): void {
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "sb_publishable_test" }));
  Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_test" }));
}

type Options = {
  role?: string;
  /** رد تعديل مستخدم Auth (الافتراضي 200). */
  putStatus?: number;
  /** هل يقبل الدليل التسجيل؟ */
  directoryAccepts?: boolean;
};

/** خادم المدرسة والدليل الوهميان: جلسة المستدعي وكلمة سره وتعديل المستخدم واستدعاءات الدليل. */
function platform(seen: Seen, options: Options): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    let response: Response | undefined;
    if (url.pathname === "/auth/v1/user") {
      response = headers.get("authorization") === "Bearer user-jwt"
        ? Response.json({ id: "caller-1", email: OLD_EMAIL })
        : new Response("no session", { status: 401 });
    } else if (url.pathname === "/rest/v1/user_accounts") {
      response = Response.json([{ id: "caller-1", role: options.role ?? "owner", entity_id: null }]);
    } else if (url.pathname === "/rest/v1/workers") {
      response = Response.json([{ permissions: "{}" }]);
    } else if (url.pathname === "/auth/v1/token") {
      const sent = JSON.parse(String(init?.body));
      seen.checks.push({ email: sent.email, password: sent.password });
      response = sent.email === OLD_EMAIL && sent.password === OLD_PASSWORD
        ? Response.json({ access_token: "token" })
        : Response.json({ error_code: "invalid_credentials" }, { status: 400 });
    } else if (url.pathname === "/auth/v1/admin/users/caller-1" && init?.method === "PUT") {
      const sent = JSON.parse(String(init.body));
      seen.puts.push({ email: sent.email, confirm: sent.email_confirm, apikey: headers.get("apikey") });
      response = (options.putStatus ?? 200) === 200
        ? Response.json({ id: "caller-1" })
        : Response.json({ error_code: "email_exists" }, { status: options.putStatus });
    } else if (url.pathname.startsWith("/rest/v1/rpc/school_")) {
      const sent = JSON.parse(String(init?.body));
      seen.directory.push({ fn: url.pathname.split("/").pop() ?? "", phone: sent.p_phone });
      response = Response.json(options.directoryAccepts ?? true);
    }
    return Promise.resolve(response ?? new Response("unexpected " + url.pathname, { status: 500 }));
  }) as typeof fetch;
}

function request(body: unknown, authorization = "Bearer user-jwt"): Request {
  return new Request("https://functions.test/change-login", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function run(
  body: unknown,
  options: Options = {},
  withDirectory = false,
): Promise<{ status: number; text: string; seen: Seen }> {
  const seen: Seen = { puts: [], checks: [], directory: [] };
  const original = globalThis.fetch;
  configure();
  if (withDirectory) {
    Deno.env.set("DIRECTORY_URL", "https://dir.supabase.co");
    Deno.env.set("DIRECTORY_ANON_KEY", "sb_publishable_dir");
    Deno.env.set("DIRECTORY_SLUG", "alnour");
    Deno.env.set("DIRECTORY_REGISTER_KEY", "k".repeat(64));
  }
  globalThis.fetch = platform(seen, options);
  try {
    const response = await handle(request(body));
    return { status: response.status, text: await response.text(), seen };
  } finally {
    globalThis.fetch = original;
    for (const name of DIRECTORY_NAMES) Deno.env.delete(name);
  }
}

const good = { new_email: NEW_EMAIL, current_password: OLD_PASSWORD };

Deno.test("the owner changes the login phone after proving the current password", async () => {
  const result = await run(good);
  assert(result.status === 200 && result.text === JSON.stringify({ ok: true }), `${result.status} ${result.text}`);
  assert(
    result.seen.checks.length === 1 && result.seen.checks[0].email === OLD_EMAIL &&
      result.seen.checks[0].password === OLD_PASSWORD,
    "the current password is checked against the current login",
  );
  assert(
    result.seen.puts.length === 1 && result.seen.puts[0].email === NEW_EMAIL &&
      result.seen.puts[0].confirm === true && result.seen.puts[0].apikey === "sb_secret_test",
    JSON.stringify(result.seen.puts),
  );
  assert(!result.text.includes(OLD_PASSWORD), "the password is never echoed");
});

Deno.test("a worker may change its own login too", async () => {
  const result = await run(good, { role: "worker" });
  assert(result.status === 200, `${result.status} ${result.text}`);
});

Deno.test("teachers and parents cannot change their login themselves", async () => {
  for (const role of ["teacher", "parent"]) {
    const result = await run(good, { role });
    assert(result.status === 403, `${role}: ${result.status}`);
    assert(result.seen.puts.length === 0 && result.seen.checks.length === 0, `${role}: nothing touched`);
  }
});

Deno.test("a wrong current password is refused and changes nothing", async () => {
  const result = await run({ ...good, current_password: "not-the-password" });
  assert(result.status === 403 && result.text.includes("wrong_password"), `${result.status} ${result.text}`);
  assert(result.seen.puts.length === 0, "the login is untouched");
});

Deno.test("only a phone-based login may be the new one, and it must differ", async () => {
  for (
    const body of [
      { ...good, new_email: "owner@school.com" },
      { ...good, new_email: "0150123456@school.local" },
      { ...good, new_email: 5 },
      { ...good, current_password: "" },
      { new_email: NEW_EMAIL },
      "not an object",
    ]
  ) {
    const result = await run(body);
    assert(result.status === 400, `${JSON.stringify(body)}: ${result.status}`);
    assert(result.seen.puts.length === 0, "nothing is changed for a bad request");
  }
  const same = await run({ ...good, new_email: OLD_EMAIL.toUpperCase() });
  assert(same.status === 400 && same.text.includes("same_email"), `${same.status} ${same.text}`);
});

Deno.test("a phone already used by another account is a 409", async () => {
  for (const putStatus of [409, 422]) {
    const result = await run(good, { putStatus });
    assert(result.status === 409 && result.text.includes("email_exists"), `${putStatus}: ${result.status}`);
  }
  const failing = await run(good, { putStatus: 500 });
  assert(failing.status === 502, String(failing.status));
});

Deno.test("with a directory the new phone is registered and the old one removed", async () => {
  const result = await run(good, {}, true);
  assert(result.status === 200, `${result.status} ${result.text}`);
  assert(
    result.seen.directory.length === 2 &&
      result.seen.directory[0].fn === "school_register_phone" &&
      result.seen.directory[0].phone === "0661234567" &&
      result.seen.directory[1].fn === "school_unregister_phone" &&
      result.seen.directory[1].phone === "0550123456",
    JSON.stringify(result.seen.directory),
  );
});

Deno.test("when the directory refuses the new phone the old login is restored", async () => {
  const result = await run(good, { directoryAccepts: false }, true);
  assert(result.status === 502 && result.text.includes("directory_unavailable"), `${result.status} ${result.text}`);
  assert(
    result.seen.puts.length === 2 && result.seen.puts[0].email === NEW_EMAIL &&
      result.seen.puts[1].email === OLD_EMAIL,
    JSON.stringify(result.seen.puts),
  );
  assert(
    result.seen.directory.every((call) => call.fn === "school_register_phone"),
    "the old phone stays registered",
  );
});

Deno.test("without a directory no directory call is made", async () => {
  const result = await run(good);
  assert(result.status === 200 && result.seen.directory.length === 0, `${result.status}`);
});

Deno.test("no bearer token or an invalid session is a 401", async () => {
  configure();
  const original = globalThis.fetch;
  globalThis.fetch = platform({ puts: [], checks: [], directory: [] }, {});
  try {
    assert((await handle(request(good, ""))).status === 401, "missing header");
    assert((await handle(request(good, "Bearer expired"))).status === 401, "invalid session");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("without server keys the function reports it is not configured", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_SECRET_KEYS", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  const saved = names.map((n) => [n, Deno.env.get(n)] as const);
  try {
    for (const n of names) Deno.env.delete(n);
    const response = await handle(request(good));
    assert(response.status === 503, String(response.status));
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

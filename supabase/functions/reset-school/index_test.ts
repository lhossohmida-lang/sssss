import { CONFIRMATION, handle } from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const OWNER_EMAIL = "0550123456@school.local";
const PASSWORD = "Owner-Sentinel-Pass-1";
const EPOCH = "11111111-2222-3333-4444-555555555555";
const DIRECTORY_NAMES = ["DIRECTORY_URL", "DIRECTORY_ANON_KEY", "DIRECTORY_SLUG", "DIRECTORY_REGISTER_KEY"];

type Seen = {
  checks: { email: unknown; password: unknown }[];
  resets: { body: Record<string, unknown>; apikey: string | null }[];
  deletedUsers: string[];
  storage: { bucket: string; names: string[] }[];
  directory: { fn: string; phone: unknown }[];
  order: string[];
};

type Options = {
  role?: string;
  /** هل تنجح دالة SQL؟ (الافتراضي نعم) */
  resetOk?: boolean;
  /** حسابات الدخول في خدمة Auth (غير المحذوفة صفوفها). */
  authUsers?: { id: string; email: string }[];
  /** معرّفات حسابات يفشل حذفها (500). */
  failDelete?: string[];
  /** حسابات تعيد 404 عند الحذف (محذوفة من قبل). */
  missing?: string[];
  directoryAccepts?: boolean;
  storageStatus?: number;
  /** أصحاب مدرسة آخرون سوى المستدعي. */
  otherOwners?: string[];
};

const removedAccounts = [
  { id: "acc-w1", email: "0661111111@school.local", role: "worker" },
  { id: "acc-t1", email: "0662222222@school.local", role: "teacher" },
  { id: "acc-p1", email: "0773333333@school.local", role: "parent" },
];
const objects = [
  { bucket: "photos", name: "students/a.jpg" },
  { bucket: "photos", name: "students/b.jpg" },
  { bucket: "files", name: "chat/c.pdf" },
];

function configure(): void {
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "sb_publishable_test" }));
  Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_test" }));
}

/** خادم المدرسة والدليل الوهميان. */
function platform(seen: Seen, options: Options): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    const method = init?.method ?? "GET";
    let response: Response | undefined;
    if (url.pathname === "/auth/v1/user") {
      response = headers.get("authorization") === "Bearer user-jwt"
        ? Response.json({ id: "caller-1", email: OWNER_EMAIL })
        : new Response("no session", { status: 401 });
    } else if (url.pathname === "/rest/v1/user_accounts") {
      const select = url.searchParams.get("select");
      if (select === "id,role,entity_id") {
        response = Response.json([{ id: "caller-1", role: options.role ?? "owner", entity_id: null }]);
      } else if (select === "display_name") {
        response = Response.json([{ display_name: "المدير" }]);
      } else {
        response = Response.json([{ id: "caller-1" }, ...(options.otherOwners ?? []).map((id) => ({ id }))]);
      }
    } else if (url.pathname === "/rest/v1/workers") {
      response = Response.json([{ permissions: "{}" }]);
    } else if (url.pathname === "/auth/v1/token") {
      const sent = JSON.parse(String(init?.body));
      seen.checks.push({ email: sent.email, password: sent.password });
      response = sent.email === OWNER_EMAIL && sent.password === PASSWORD
        ? Response.json({ access_token: "token" })
        : Response.json({ error_code: "invalid_credentials" }, { status: 400 });
    } else if (url.pathname === "/rest/v1/rpc/reset_school_data") {
      seen.order.push("reset");
      seen.resets.push({ body: JSON.parse(String(init?.body)), apikey: headers.get("apikey") });
      response = options.resetOk === false
        ? new Response("boom", { status: 500 })
        : Response.json({ epoch: EPOCH, removed: removedAccounts, objects });
    } else if (url.pathname === "/auth/v1/admin/users" && method === "GET") {
      const page = Number(url.searchParams.get("page") ?? "1");
      response = Response.json({
        users: page === 1 ? [{ id: "caller-1", email: OWNER_EMAIL }, ...(options.authUsers ?? [])] : [],
      });
    } else if (url.pathname.startsWith("/auth/v1/admin/users/") && method === "DELETE") {
      const id = decodeURIComponent(url.pathname.split("/").pop() ?? "");
      seen.order.push("auth");
      if (options.failDelete?.includes(id)) {
        response = new Response("no", { status: 500 });
      } else if (options.missing?.includes(id)) {
        response = new Response("gone", { status: 404 });
      } else {
        seen.deletedUsers.push(id);
        response = Response.json({ id });
      }
    } else if (url.pathname.startsWith("/rest/v1/rpc/school_")) {
      const sent = JSON.parse(String(init?.body));
      seen.directory.push({ fn: url.pathname.split("/").pop() ?? "", phone: sent.p_phone });
      response = Response.json(options.directoryAccepts ?? true);
    } else if (url.pathname.startsWith("/storage/v1/object/") && method === "DELETE") {
      const bucket = decodeURIComponent(url.pathname.split("/").pop() ?? "");
      const sent = JSON.parse(String(init?.body));
      seen.storage.push({ bucket, names: sent.prefixes });
      response = new Response("[]", { status: options.storageStatus ?? 200 });
    }
    return Promise.resolve(response ?? new Response("unexpected " + url.pathname, { status: 500 }));
  }) as typeof fetch;
}

function request(body: unknown, authorization = "Bearer user-jwt"): Request {
  return new Request("https://functions.test/reset-school", {
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
  const seen: Seen = { checks: [], resets: [], deletedUsers: [], storage: [], directory: [], order: [] };
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

const good = { current_password: PASSWORD, confirm: CONFIRMATION };

Deno.test("the owner resets the school after the password and the confirmation phrase", async () => {
  const result = await run(good, {}, true);
  assert(result.status === 200, `${result.status} ${result.text}`);
  const reply = JSON.parse(result.text);
  assert(reply.ok === true && reply.epoch === EPOCH && reply.removed_accounts === 3, result.text);
  assert(
    reply.failures.auth === 0 && reply.failures.directory === 0 && reply.failures.storage === 0,
    result.text,
  );
  assert(
    result.seen.checks.length === 1 && result.seen.checks[0].email === OWNER_EMAIL &&
      result.seen.checks[0].password === PASSWORD,
    "the password is checked against the owner's login",
  );
  assert(
    result.seen.resets.length === 1 && result.seen.resets[0].body.p_actor_id === "caller-1" &&
      result.seen.resets[0].body.p_actor_name === "المدير" && result.seen.resets[0].apikey === "sb_secret_test",
    JSON.stringify(result.seen.resets),
  );
  assert(!result.text.includes(PASSWORD), "the password is never echoed");
  // الحسابات المحذوفة من الدخول، ولا يُحذف المالك.
  assert(
    [...result.seen.deletedUsers].sort().join() === "acc-p1,acc-t1,acc-w1",
    JSON.stringify(result.seen.deletedUsers),
  );
  // الدليل: هاتف العامل وحده (الأساتذة والأولياء ليسوا في الدليل).
  assert(
    result.seen.directory.length === 1 && result.seen.directory[0].fn === "school_unregister_phone" &&
      result.seen.directory[0].phone === "0661111111",
    JSON.stringify(result.seen.directory),
  );
  // الملفات بواجهة التخزين لكل مخزن.
  assert(
    result.seen.storage.length === 2 &&
      result.seen.storage.find((s) => s.bucket === "photos")?.names.join() === "students/a.jpg,students/b.jpg" &&
      result.seen.storage.find((s) => s.bucket === "files")?.names.join() === "chat/c.pdf",
    JSON.stringify(result.seen.storage),
  );
  // البيانات تُمسح أولاً: لا يُحذف حساب دخول قبلها.
  assert(result.seen.order[0] === "reset", result.seen.order.join());
});

Deno.test("without a directory no directory call is made", async () => {
  const result = await run(good);
  assert(result.status === 200 && result.seen.directory.length === 0, `${result.status}`);
});

Deno.test("orphan phone logins are swept, other owners and non-phone logins are kept", async () => {
  const result = await run(good, {
    otherOwners: ["owner-2"],
    authUsers: [
      { id: "orphan-1", email: "0771234567@school.local" },
      { id: "owner-2", email: "0550999999@school.local" },
      { id: "dev-1", email: "developer@example.com" },
    ],
  });
  assert(result.status === 200, `${result.status} ${result.text}`);
  const deleted = [...result.seen.deletedUsers].sort().join();
  assert(deleted === "acc-p1,acc-t1,acc-w1,orphan-1", deleted);
});

Deno.test("only the owner may reset the school", async () => {
  for (const role of ["worker", "teacher", "parent"]) {
    const result = await run(good, { role });
    assert(result.status === 403, `${role}: ${result.status}`);
    assert(
      result.seen.resets.length === 0 && result.seen.checks.length === 0 &&
        result.seen.deletedUsers.length === 0,
      `${role}: nothing touched`,
    );
  }
});

Deno.test("a wrong password is refused and nothing is deleted", async () => {
  const result = await run({ ...good, current_password: "not-the-password" });
  assert(result.status === 403 && result.text.includes("wrong_password"), `${result.status} ${result.text}`);
  assert(result.seen.resets.length === 0 && result.seen.deletedUsers.length === 0, "untouched");
});

Deno.test("a request without the confirmation phrase or the password is refused", async () => {
  for (
    const body of [
      { current_password: PASSWORD },
      { current_password: PASSWORD, confirm: "yes" },
      { current_password: PASSWORD, confirm: CONFIRMATION.toLowerCase() },
      { current_password: "", confirm: CONFIRMATION },
      { confirm: CONFIRMATION },
      { current_password: 5, confirm: CONFIRMATION },
      "not an object",
    ]
  ) {
    const result = await run(body);
    assert(result.status === 400, `${JSON.stringify(body)}: ${result.status}`);
    assert(result.seen.resets.length === 0 && result.seen.checks.length === 0, "nothing is touched");
  }
});

Deno.test("when the data reset fails nothing else is deleted", async () => {
  const result = await run(good, { resetOk: false }, true);
  assert(result.status === 502 && result.text.includes("reset_failed"), `${result.status} ${result.text}`);
  assert(
    result.seen.deletedUsers.length === 0 && result.seen.directory.length === 0 && result.seen.storage.length === 0,
    "no logins, directory entries or files are removed",
  );
});

Deno.test("what could not be removed afterwards is counted so the owner can run it again", async () => {
  const result = await run(
    good,
    { failDelete: ["acc-t1"], missing: ["acc-p1"], directoryAccepts: false, storageStatus: 500 },
    true,
  );
  assert(result.status === 200, `${result.status} ${result.text}`);
  const reply = JSON.parse(result.text);
  assert(reply.ok === true && reply.epoch === EPOCH, result.text);
  assert(
    reply.failures.auth === 1 && reply.failures.directory === 1 && reply.failures.storage === 3,
    "a 404 counts as removed; the rest are counted: " + result.text,
  );
});

Deno.test("no bearer token or an invalid session is a 401", async () => {
  configure();
  const original = globalThis.fetch;
  globalThis.fetch = platform(
    { checks: [], resets: [], deletedUsers: [], storage: [], directory: [], order: [] },
    {},
  );
  try {
    const none = await handle(
      new Request("https://functions.test/reset-school", {
        method: "POST",
        body: JSON.stringify(good),
      }),
    );
    assert(none.status === 401, String(none.status));
    const bad = await handle(request(good, "Bearer other-jwt"));
    assert(bad.status === 401, String(bad.status));
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("method, preflight and missing configuration are answered cleanly", async () => {
  configure();
  const get = await handle(new Request("https://functions.test/reset-school", { method: "GET" }));
  assert(get.status === 405, String(get.status));
  const options = await handle(new Request("https://functions.test/reset-school", { method: "OPTIONS" }));
  assert(options.status === 200, String(options.status));
  Deno.env.delete("SUPABASE_SECRET_KEYS");
  try {
    const result = await handle(request(good));
    assert(result.status === 503, String(result.status));
  } finally {
    configure();
  }
});

Deno.test("malformed json is a 400", async () => {
  configure();
  const response = await handle(
    new Request("https://functions.test/reset-school", {
      method: "POST",
      headers: { authorization: "Bearer user-jwt" },
      body: "{not json",
    }),
  );
  assert(response.status === 400, String(response.status));
});

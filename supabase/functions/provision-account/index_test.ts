import { handle } from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

type Route = (url: URL, init?: RequestInit) => Response | undefined;

const PASSWORD = "Sentinel-Pass-123";

function configure(): void {
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "sb_publishable_test" }));
  Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_test" }));
}

/** الخادم الوهمي: جلسة المستدعي ودوره وصلاحياته، وما تبقى يُمرَّر إلى [extra]. */
function platform(caller: { role: string; permissions?: unknown }, extra: Route): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    let response: Response | undefined;
    if (url.pathname === "/auth/v1/user") {
      response = headers.get("authorization") === "Bearer user-jwt"
        ? Response.json({ id: "caller-1" })
        : new Response("no session", { status: 401 });
    } else if (url.pathname === "/rest/v1/user_accounts") {
      response = Response.json([{ id: "caller-1", role: caller.role, entity_id: "e-1" }]);
    } else if (url.pathname === "/rest/v1/workers") {
      response = Response.json([{ permissions: JSON.stringify(caller.permissions ?? {}) }]);
    } else {
      response = extra(url, init);
    }
    return Promise.resolve(response ?? new Response("unexpected " + url.pathname, { status: 500 }));
  }) as typeof fetch;
}

function request(body: unknown, authorization = "Bearer user-jwt"): Request {
  return new Request("https://functions.test/provision-account", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function run(
  caller: { role: string; permissions?: unknown },
  body: unknown,
  extra: Route = () => undefined,
): Promise<{ status: number; text: string }> {
  const original = globalThis.fetch;
  configure();
  globalThis.fetch = platform(caller, extra);
  try {
    const response = await handle(request(body));
    return { status: response.status, text: await response.text() };
  } finally {
    globalThis.fetch = original;
  }
}

const createdUser: Route = (url, init) => {
  if (url.pathname !== "/auth/v1/admin/users" || init?.method !== "POST") return undefined;
  const headers = new Headers(init.headers);
  assert(headers.get("apikey") === "sb_secret_test", "the secret key is sent in apikey");
  assert(headers.get("authorization") === null, "a non-JWT key is not sent as a bearer token");
  const sent = JSON.parse(String(init.body));
  assert(sent.email_confirm === true && sent.email === "0550123456@school.local", "confirmed email");
  return Response.json({ id: "new-user-1" });
};

Deno.test("the owner creates a parent account and gets the new id back", async () => {
  const result = await run(
    { role: "owner" },
    { email: "0550123456@school.local", password: PASSWORD, role: "parent" },
    createdUser,
  );
  assert(result.status === 200 && result.text === JSON.stringify({ id: "new-user-1" }), result.text);
  assert(!result.text.includes(PASSWORD), "the password is never echoed");
});

Deno.test("a worker may create only what its permissions allow", async () => {
  const worker = { role: "worker", permissions: { teachers: ["add"] } };
  const body = (role: string) => ({ email: "0550123456@school.local", password: PASSWORD, role });
  assert((await run(worker, body("teacher"), createdUser)).status === 200, "teacher allowed");
  assert((await run(worker, body("parent"), createdUser)).status === 403, "parent refused");
  assert((await run(worker, body("worker"), createdUser)).status === 403, "worker refused");
  assert((await run(worker, body("owner"), createdUser)).status === 403, "owner refused");
});

Deno.test("teachers and parents cannot create accounts", async () => {
  for (const role of ["teacher", "parent"]) {
    const result = await run(
      { role },
      { email: "0550123456@school.local", password: PASSWORD, role: "parent" },
      createdUser,
    );
    assert(result.status === 403, role);
  }
});

Deno.test("bad requests are refused before any session lookup matters", async () => {
  const good = { email: "0550123456@school.local", password: PASSWORD, role: "parent" };
  for (const body of [
    { ...good, email: "no-at-sign" },
    { ...good, password: "short" },
    { ...good, role: "admin" },
    { password: PASSWORD, role: "parent" },
    "not an object",
  ]) {
    assert((await run({ role: "owner" }, body, createdUser)).status === 400, JSON.stringify(body));
  }
});

Deno.test("an existing email is a 409 conflict", async () => {
  const result = await run(
    { role: "owner" },
    { email: "0550123456@school.local", password: PASSWORD, role: "parent" },
    (url) => url.pathname === "/auth/v1/admin/users"
      ? Response.json({ error_code: "email_exists" }, { status: 422 })
      : undefined,
  );
  assert(result.status === 409, String(result.status));
});

Deno.test("no bearer token or an invalid session is a 401", async () => {
  configure();
  const original = globalThis.fetch;
  globalThis.fetch = platform({ role: "owner" }, () => undefined);
  try {
    const body = { email: "0550123456@school.local", password: PASSWORD, role: "parent" };
    assert((await handle(request(body, ""))).status === 401, "missing header");
    assert((await handle(request(body, "Bearer expired"))).status === 401, "invalid session");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("without server keys the function reports it is not configured", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_SECRET_KEYS", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  const saved = names.map((n) => [n, Deno.env.get(n)] as const);
  try {
    for (const n of names) Deno.env.delete(n);
    const response = await handle(request({ email: "a@b.co", password: PASSWORD, role: "parent" }));
    assert(response.status === 503, String(response.status));
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

Deno.test("a failing auth service gives a 502 and logs no password", async () => {
  const logged: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logged.push(args.map(String).join(" "));
  };
  try {
    const result = await run(
      { role: "owner" },
      { email: "0550123456@school.local", password: PASSWORD, role: "parent" },
      (url) => url.pathname === "/auth/v1/admin/users" ? new Response("boom", { status: 500 }) : undefined,
    );
    assert(result.status === 502, String(result.status));
    assert(!result.text.includes(PASSWORD) && !logged.join("\n").includes(PASSWORD), "no password leaked");
  } finally {
    console.error = original;
  }
});

const DIRECTORY_NAMES = ["DIRECTORY_URL", "DIRECTORY_ANON_KEY", "DIRECTORY_SLUG", "DIRECTORY_REGISTER_KEY"];
const REGISTER_KEY = "k".repeat(64);

/** يضبط أسرار الدليل أثناء [action] ثم يمسحها لئلا تؤثر في بقية الاختبارات. */
async function withDirectory<T>(action: () => Promise<T>): Promise<T> {
  Deno.env.set("DIRECTORY_URL", "https://dir.supabase.co");
  Deno.env.set("DIRECTORY_ANON_KEY", "sb_publishable_dir");
  Deno.env.set("DIRECTORY_SLUG", "alnour");
  Deno.env.set("DIRECTORY_REGISTER_KEY", REGISTER_KEY);
  try {
    return await action();
  } finally {
    for (const name of DIRECTORY_NAMES) Deno.env.delete(name);
  }
}

/** يجرّب المسارات بالترتيب ويعيد أول رد. */
function first(...routes: Route[]): Route {
  return (url, init) => {
    for (const route of routes) {
      const response = route(url, init);
      if (response !== undefined) return response;
    }
    return undefined;
  };
}

type DirectoryCall = { phone: string; slug: string; key: string; apikey: string | null };

/** دليل وهمي يسجّل ما استُدعي به ويجيب [answer] (قيمة JSON أو رمز حالة خطأ). */
function directory(calls: DirectoryCall[], answer: boolean | number): Route {
  return (url, init) => {
    if (url.pathname !== "/rest/v1/rpc/school_register_phone") return undefined;
    const sent = JSON.parse(String(init?.body));
    calls.push({
      phone: sent.p_phone,
      slug: sent.p_slug,
      key: sent.p_register_key,
      apikey: new Headers(init?.headers).get("apikey"),
    });
    return typeof answer === "number" ? new Response("no", { status: answer }) : Response.json(answer);
  };
}

Deno.test("an owner or worker account is registered in the school directory with the school's key", async () => {
  for (const role of ["worker", "owner"]) {
    const calls: DirectoryCall[] = [];
    const result = await withDirectory(() =>
      run(
        { role: "owner" },
        { email: "0550123456@school.local", password: PASSWORD, role },
        first(createdUser, directory(calls, true)),
      )
    );
    assert(result.status === 200, `${role}: ${result.status} ${result.text}`);
    assert(calls.length === 1, `${role}: one directory call`);
    assert(
      calls[0].phone === "0550123456" && calls[0].slug === "alnour" && calls[0].key === REGISTER_KEY,
      `${role}: payload`,
    );
    assert(calls[0].apikey === "sb_publishable_dir", `${role}: the directory public key`);
  }
});

Deno.test("teachers, parents and non-phone logins are not registered in the directory", async () => {
  const created: Route = (url, init) => {
    if (url.pathname !== "/auth/v1/admin/users" || init?.method !== "POST") return undefined;
    return Response.json({ id: "new-user-1" });
  };
  const cases = [
    { role: "teacher", email: "0550123456@school.local" },
    { role: "parent", email: "0550123456@school.local" },
    { role: "worker", email: "worker@school.com" },
  ];
  for (const { role, email } of cases) {
    const calls: DirectoryCall[] = [];
    const result = await withDirectory(() =>
      run({ role: "owner" }, { email, password: PASSWORD, role }, first(created, directory(calls, true)))
    );
    assert(result.status === 200, `${role}: ${result.status}`);
    assert(calls.length === 0, `${role}: no directory call`);
  }
});

Deno.test("when the directory refuses, the new user is deleted and the request fails", async () => {
  for (const answer of [false, 500]) {
    const calls: DirectoryCall[] = [];
    const deleted: string[] = [];
    const removal: Route = (url, init) => {
      if (init?.method !== "DELETE") return undefined;
      deleted.push(url.pathname);
      return new Response(null, { status: 200 });
    };
    const result = await withDirectory(() =>
      run(
        { role: "owner" },
        { email: "0550123456@school.local", password: PASSWORD, role: "worker" },
        first(createdUser, removal, directory(calls, answer)),
      )
    );
    assert(result.status === 502 && result.text.includes("directory_unavailable"), `${answer}: ${result.status}`);
    assert(
      deleted.length === 1 && deleted[0] === "/auth/v1/admin/users/new-user-1",
      `${answer}: the new user is removed (${deleted.join(",")})`,
    );
    assert(!result.text.includes("new-user-1"), "the id of the removed user is not returned");
  }
});

Deno.test("without directory secrets no directory call is made", async () => {
  const calls: DirectoryCall[] = [];
  const result = await run(
    { role: "owner" },
    { email: "0550123456@school.local", password: PASSWORD, role: "worker" },
    first(createdUser, directory(calls, true)),
  );
  assert(result.status === 200 && calls.length === 0, `${result.status} ${calls.length}`);
});

Deno.test("an account made offline keeps its client-chosen id, also on a retry", async () => {
  const id = "8f0e2a4c-1b3d-4e5f-9a7b-6c5d4e3f2a1b";
  const body = { email: "0550123456@school.local", password: PASSWORD, role: "parent", id };
  const withId: Route = (url, init) => {
    if (url.pathname !== "/auth/v1/admin/users" || init?.method !== "POST") return undefined;
    assert(JSON.parse(String(init.body)).id === id, "the requested id is passed to auth");
    return Response.json({ id });
  };
  const first = await run({ role: "owner" }, body, withId);
  assert(first.status === 200 && first.text === JSON.stringify({ id }), first.text);

  // The first reply was lost: auth now says the email exists, and the user with that id is ours.
  const retry: Route = (url, init) => {
    if (url.pathname === "/auth/v1/admin/users" && init?.method === "POST") {
      return new Response("exists", { status: 422 });
    }
    if (url.pathname === `/auth/v1/admin/users/${id}`) {
      return Response.json({ id, email: "0550123456@school.local" });
    }
    return undefined;
  };
  const again = await run({ role: "owner" }, body, retry);
  assert(again.status === 200 && again.text === JSON.stringify({ id }), again.text);

  const bad = await run({ role: "owner" }, { ...body, id: "not-a-uuid" }, withId);
  assert(bad.status === 400, "a malformed id is refused");
});

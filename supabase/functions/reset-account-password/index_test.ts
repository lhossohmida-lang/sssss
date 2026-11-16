import { handle } from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

type Route = (url: URL, init?: RequestInit) => Response | undefined;

const PASSWORD = "Sentinel-New-Pass-1";
const TARGET = "0b1f6f0e-6f1d-4d5e-9c43-1c2c5b7a9e10";

function configure(): void {
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "sb_publishable_test" }));
  Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_test" }));
}

/** الخادم الوهمي: جلسة المستدعي ودوره وصلاحياته ودور الحساب المستهدف. */
function platform(
  caller: { role: string; permissions?: unknown },
  targetRole: string | null,
  extra: Route,
): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    let response: Response | undefined;
    if (url.pathname === "/auth/v1/user") {
      response = headers.get("authorization") === "Bearer user-jwt"
        ? Response.json({ id: "caller-1" })
        : new Response("no session", { status: 401 });
    } else if (url.pathname === "/rest/v1/user_accounts") {
      const wanted = url.searchParams.get("id");
      if (wanted === "eq.caller-1") {
        response = Response.json([{ id: "caller-1", role: caller.role, entity_id: "e-1" }]);
      } else if (wanted === `eq.${TARGET}`) {
        response = Response.json(targetRole === null ? [] : [{ role: targetRole }]);
      }
    } else if (url.pathname === "/rest/v1/workers") {
      response = Response.json([{ permissions: JSON.stringify(caller.permissions ?? {}) }]);
    } else {
      response = extra(url, init);
    }
    return Promise.resolve(response ?? new Response("unexpected " + url.pathname, { status: 500 }));
  }) as typeof fetch;
}

async function run(
  caller: { role: string; permissions?: unknown },
  targetRole: string | null,
  body: unknown,
  extra: Route = () => undefined,
): Promise<{ status: number; text: string }> {
  const original = globalThis.fetch;
  configure();
  globalThis.fetch = platform(caller, targetRole, extra);
  try {
    const response = await handle(
      new Request("https://functions.test/reset-account-password", {
        method: "POST",
        headers: { authorization: "Bearer user-jwt", "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
    return { status: response.status, text: await response.text() };
  } finally {
    globalThis.fetch = original;
  }
}

const updatedUser: Route = (url, init) => {
  if (url.pathname !== `/auth/v1/admin/users/${TARGET}` || init?.method !== "PUT") return undefined;
  const headers = new Headers(init.headers);
  assert(headers.get("apikey") === "sb_secret_test", "the secret key is sent in apikey");
  assert(JSON.parse(String(init.body)).password === PASSWORD, "the new password is forwarded");
  return Response.json({ id: TARGET });
};

Deno.test("the owner resets any account's password", async () => {
  for (const role of ["owner", "worker", "teacher", "parent"]) {
    const result = await run({ role: "owner" }, role, { id: TARGET, password: PASSWORD }, updatedUser);
    assert(result.status === 200 && result.text === JSON.stringify({ ok: true }), `${role}: ${result.text}`);
    assert(!result.text.includes(PASSWORD), "the password is never echoed");
  }
});

Deno.test("a worker resets only the accounts its edit permissions cover", async () => {
  const worker = { role: "worker", permissions: { teachers: ["edit"] } };
  const body = { id: TARGET, password: PASSWORD };
  assert((await run(worker, "teacher", body, updatedUser)).status === 200, "teacher allowed");
  assert((await run(worker, "parent", body, updatedUser)).status === 403, "parent refused");
  assert((await run(worker, "owner", body, updatedUser)).status === 403, "owner refused");
});

Deno.test("teachers and parents cannot reset passwords", async () => {
  for (const role of ["teacher", "parent"]) {
    const result = await run({ role }, "parent", { id: TARGET, password: PASSWORD }, updatedUser);
    assert(result.status === 403, role);
  }
});

Deno.test("an unknown or hidden target account is a 404", async () => {
  const result = await run({ role: "owner" }, null, { id: TARGET, password: PASSWORD }, updatedUser);
  assert(result.status === 404, String(result.status));
});

Deno.test("bad requests are refused", async () => {
  for (const body of [
    { id: "not-a-uuid", password: PASSWORD },
    { id: TARGET, password: "short" },
    { password: PASSWORD },
    "not an object",
  ]) {
    assert((await run({ role: "owner" }, "teacher", body, updatedUser)).status === 400, JSON.stringify(body));
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
      "teacher",
      { id: TARGET, password: PASSWORD },
      (url) => url.pathname === `/auth/v1/admin/users/${TARGET}` ? new Response("boom", { status: 500 }) : undefined,
    );
    assert(result.status === 502, String(result.status));
    assert(!result.text.includes(PASSWORD) && !logged.join("\n").includes(PASSWORD), "no password leaked");
  } finally {
    console.error = original;
  }
});

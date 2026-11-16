import { handle, sameSecret } from "./index.ts";
import { resetTokenCache } from "../_shared/fcm.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const SECRET = "push-secret-0123456789abcdef0123456789abcdef";
const ENV_NAMES = [
  "PUSH_SECRET",
  "FIREBASE_SERVICE_ACCOUNT",
  "SUPABASE_URL",
  "SUPABASE_SECRET_KEYS",
  "SUPABASE_SERVICE_ROLE_KEY",
];

type Row = Record<string, unknown>;

class World {
  notifications: Row[] = [];
  chat_messages: Row[] = [];
  chat_members: Row[] = [];
  chat_rooms: Row[] = [];
  push_installations: Row[] = [];
  fcm: { fid: string; message: Row; auth: string }[] = [];
  fcmStatus: (fid: string) => number = () => 200;
  deleted: string[] = [];
  tokens: { header: Row; claims: Row; valid: boolean }[] = [];
  supabaseKeys: string[] = [];
}

async function makeAccount(): Promise<{ publicKey: CryptoKey; raw: string; privatePem: string }> {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const privatePem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(binary).match(/.{1,64}/g)!.join("\n")
  }\n-----END PRIVATE KEY-----\n`;
  return {
    publicKey: pair.publicKey,
    privatePem,
    raw: JSON.stringify({
      client_email: "push@school-test.iam.gserviceaccount.com",
      private_key: privatePem,
      project_id: "school-test",
    }),
  };
}

function decodePart(part: string): Row {
  const padded = part.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - part.length % 4) % 4);
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))));
}

function filtered(world: World, table: string, params: URLSearchParams): Row[] {
  let list = [...((world as unknown as Record<string, Row[]>)[table] ?? [])];
  for (const [column, filter] of params) {
    if (["select", "limit"].includes(column)) continue;
    if (filter.startsWith("eq.")) list = list.filter((r) => String(r[column]) === filter.slice(3));
    else if (filter === "is.null") list = list.filter((r) => r[column] == null);
    else if (filter.startsWith("in.(")) {
      const wanted = filter.slice(4, -1).split(",").map((v) => v.replaceAll('"', ""));
      list = list.filter((r) => wanted.includes(String(r[column])));
    }
  }
  return list;
}

async function withWorld<T>(
  world: World,
  env: Record<string, string | undefined>,
  account: { publicKey: CryptoKey; raw: string },
  run: () => Promise<T>,
): Promise<T> {
  const savedEnv = ENV_NAMES.map((name) => [name, Deno.env.get(name)] as const);
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const logged: string[] = [];
  console.error = (...args: unknown[]) => {
    logged.push(args.map(String).join(" "));
  };
  for (const name of ENV_NAMES) Deno.env.delete(name);
  Deno.env.set("PUSH_SECRET", SECRET);
  Deno.env.set("FIREBASE_SERVICE_ACCOUNT", account.raw);
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_test" }));
  for (const [name, value] of Object.entries(env)) {
    if (value === undefined) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }
  resetTokenCache();
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    if (url.hostname === "oauth2.googleapis.com") {
      const assertion = new URLSearchParams(String(init?.body)).get("assertion") ?? "";
      const [head, claims, signature] = assertion.split(".");
      const padded = signature.replaceAll("-", "+").replaceAll("_", "/") +
        "=".repeat((4 - signature.length % 4) % 4);
      const valid = await crypto.subtle.verify(
        "RSASSA-PKCS1-v1_5",
        account.publicKey,
        Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)),
        new TextEncoder().encode(`${head}.${claims}`),
      );
      world.tokens.push({ header: decodePart(head), claims: decodePart(claims), valid });
      return Response.json({ access_token: "access-token-1", expires_in: 3600 });
    }
    if (url.hostname === "fcm.googleapis.com") {
      assert(url.pathname === "/v1/projects/school-test/messages:send", `FCM path ${url.pathname}`);
      const message = JSON.parse(String(init?.body)).message as Row;
      const fid = String(message.fid);
      world.fcm.push({ fid, message, auth: headers.get("authorization") ?? "" });
      const status = world.fcmStatus(fid);
      return new Response(status === 200 ? "{}" : "{\"error\":{}}", { status });
    }
    if (url.hostname === "abc.supabase.co") {
      world.supabaseKeys.push(headers.get("apikey") ?? "");
      const table = url.pathname.replace("/rest/v1/", "");
      if (init?.method === "DELETE") {
        world.deleted.push(url.searchParams.get("installation_id")!.slice(3));
        return new Response(null, { status: 204 });
      }
      return Response.json(filtered(world, table, url.searchParams));
    }
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  try {
    return await run();
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
    for (const [name, value] of savedEnv) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
    assert(!logged.join("\n").includes(SECRET) && !logged.join("\n").includes("PRIVATE KEY"), "A log line leaked a secret");
  }
}

function call(body: unknown, secret: string | null = SECRET): Request {
  return new Request("https://functions.test/send-push", {
    method: "POST",
    headers: { "content-type": "application/json", ...(secret === null ? {} : { "x-push-secret": secret }) },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const account = await makeAccount();

function seeded(): World {
  const world = new World();
  world.notifications = [
    { id: "n1", user_id: "u1", title: "تذكير بالدفع", body: "عليك مستحقات الشهر", deleted_at: null },
    { id: "n-gone", user_id: "u1", title: "ح", body: "ح", deleted_at: 5 },
  ];
  world.push_installations = [
    { installation_id: "fid-u1-phone", user_id: "u1" },
    { installation_id: "fid-u1-tablet", user_id: "u1" },
    { installation_id: "fid-u2", user_id: "u2" },
    { installation_id: "fid-u3", user_id: "u3" },
  ];
  world.chat_rooms = [{ id: "r1", title: "مجموعة الرياضيات", deleted_at: null }];
  world.chat_members = [
    { room_id: "r1", user_id: "u1", deleted_at: null },
    { room_id: "r1", user_id: "u2", deleted_at: null },
    { room_id: "r1", user_id: "u3", deleted_at: 9 },
  ];
  world.chat_messages = [
    { id: "m1", room_id: "r1", sender_id: "u1", content: "ح".repeat(300), attachment_name: null, deleted_at: null },
    { id: "m-file", room_id: "r1", sender_id: "u1", content: "", attachment_name: "واجب.pdf", deleted_at: null },
    { id: "m-gone", room_id: "r1", sender_id: "u1", content: "x", attachment_name: null, deleted_at: 3 },
  ];
  return world;
}

Deno.test("only a request with the shared secret is served", async () => {
  const world = seeded();
  for (const [secret, env] of [[null, {}], ["wrong", {}], [SECRET, { PUSH_SECRET: "short" }]] as const) {
    const response = await withWorld(world, env, account, () => handle(call({ table: "notifications", id: "n1" }, secret)));
    assert(response.status === 401, `status ${response.status} for ${secret}`);
  }
  assert(world.fcm.length === 0 && world.tokens.length === 0, "A refused request still reached Firebase");
  assert(sameSecret("abc", "abc") && !sameSecret("abc", "abd") && !sameSecret("abc", "abcd"), "sameSecret");
});

Deno.test("is not configured without a Firebase service account or with a broken one", async () => {
  for (const value of [undefined, "not json", JSON.stringify({ client_email: "a@b.c" })]) {
    const response = await withWorld(seeded(), { FIREBASE_SERVICE_ACCOUNT: value }, account, () =>
      handle(call({ table: "notifications", id: "n1" })));
    assert(response.status === 503, `status ${response.status} for ${value}`);
  }
});

Deno.test("rejects malformed requests", async () => {
  for (const body of ["{", { table: "students", id: "x" }, { table: "notifications" }, { table: "notifications", id: "x".repeat(101) }]) {
    const response = await withWorld(seeded(), {}, account, () => handle(call(body)));
    assert(response.status === 400, `status ${response.status} for ${JSON.stringify(body)}`);
  }
  const get = await withWorld(seeded(), {}, account, () => handle(new Request("https://functions.test/send-push")));
  assert(get.status === 405, `GET ${get.status}`);
});

Deno.test("a notification goes to every installation of its recipient, by FID", async () => {
  const world = seeded();
  const response = await withWorld(world, {}, account, () => handle(call({ table: "notifications", id: "n1" })));
  const result = await response.json();
  assert(response.status === 200 && result.sent === 2 && result.removed === 0, JSON.stringify(result));
  assert(world.fcm.map((m) => m.fid).sort().join() === "fid-u1-phone,fid-u1-tablet", "Wrong installations");
  const message = world.fcm[0].message as { notification: Row; data: Row; android: Row };
  assert(message.notification.title === "تذكير بالدفع" && message.notification.body === "عليك مستحقات الشهر", "Text");
  assert(message.data.type === "notification" && message.data.notification_id === "n1", "Data lost");
  assert(message.android.priority === "HIGH", "Priority");
  assert(world.fcm.every((m) => m.auth === "Bearer access-token-1"), "Token not used");
  assert(world.supabaseKeys.every((k) => k === "sb_secret_test"), "Server key not sent to PostgREST");
});

Deno.test("the access token is a valid RS256 JWT for the service account and is minted once", async () => {
  const world = seeded();
  await withWorld(world, {}, account, async () => {
    await handle(call({ table: "notifications", id: "n1" }));
    await handle(call({ table: "chat_messages", id: "m1" }));
  });
  assert(world.tokens.length === 1, `minted ${world.tokens.length} times`);
  const [{ header, claims, valid }] = world.tokens;
  assert(valid, "The JWT signature does not verify with the service account's key");
  assert(header.alg === "RS256" && header.typ === "JWT", "JWT header");
  assert(claims.iss === "push@school-test.iam.gserviceaccount.com", "iss");
  assert(claims.scope === "https://www.googleapis.com/auth/firebase.messaging", "scope");
  assert(claims.aud === "https://oauth2.googleapis.com/token", "aud");
  assert(Number(claims.exp) - Number(claims.iat) === 3600, "lifetime");
});

Deno.test("a chat message goes to the other live members only, with a clipped body", async () => {
  const world = seeded();
  const response = await withWorld(world, {}, account, () => handle(call({ table: "chat_messages", id: "m1" })));
  const result = await response.json();
  assert(result.sent === 1, JSON.stringify(result));
  assert(world.fcm.length === 1 && world.fcm[0].fid === "fid-u2", `sent to ${world.fcm.map((m) => m.fid)}`);
  const message = world.fcm[0].message as { notification: { title: string; body: string }; data: Row };
  assert(message.notification.title === "مجموعة الرياضيات", "Room title");
  assert(message.notification.body.length === 120, `body ${message.notification.body.length}`);
  assert(message.data.type === "chat" && message.data.room_id === "r1", "Chat data");
});

Deno.test("an attachment without text says so, and deleted rows send nothing", async () => {
  const world = seeded();
  const file = await withWorld(world, {}, account, () => handle(call({ table: "chat_messages", id: "m-file" })));
  assert((await file.json()).sent === 1, "attachment");
  assert((world.fcm[0].message as { notification: { body: string } }).notification.body === "مرفق جديد", "Attachment text");
  world.fcm.length = 0;
  for (const [table, id] of [["chat_messages", "m-gone"], ["notifications", "n-gone"], ["notifications", "missing"]]) {
    const response = await withWorld(world, {}, account, () => handle(call({ table, id })));
    const result = await response.json();
    assert(response.status === 200 && result.sent === 0, `${id}: ${JSON.stringify(result)}`);
  }
  assert(world.fcm.length === 0, "A deleted or missing row was pushed");
});

Deno.test("an installation Firebase no longer knows is removed; other failures keep it", async () => {
  const world = seeded();
  world.fcmStatus = (fid) => fid === "fid-u1-phone" ? 404 : fid === "fid-u1-tablet" ? 500 : 200;
  const response = await withWorld(world, {}, account, () => handle(call({ table: "notifications", id: "n1" })));
  const result = await response.json();
  assert(result.sent === 0 && result.removed === 1, JSON.stringify(result));
  assert(world.deleted.join() === "fid-u1-phone", `deleted ${world.deleted}`);
});

Deno.test("a recipient without installations costs no Firebase call", async () => {
  const world = seeded();
  world.notifications.push({ id: "n-nobody", user_id: "u-none", title: "ع", body: "ب", deleted_at: null });
  const response = await withWorld(world, {}, account, () => handle(call({ table: "notifications", id: "n-nobody" })));
  assert((await response.json()).sent === 0 && world.tokens.length === 0 && world.fcm.length === 0, "Unneeded work");
});

Deno.test("a token endpoint failure is a clean 502 without details", async () => {
  const world = seeded();
  const original = globalThis.fetch;
  const response = await withWorld(world, {}, account, async () => {
    const wrapped = globalThis.fetch;
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      return url.hostname === "oauth2.googleapis.com"
        ? Promise.resolve(new Response("denied", { status: 401 }))
        : wrapped(input, init);
    }) as typeof fetch;
    try {
      return await handle(call({ table: "notifications", id: "n1" }));
    } finally {
      globalThis.fetch = wrapped;
    }
  });
  globalThis.fetch = original;
  const text = await response.text();
  assert(response.status === 502 && JSON.parse(text).error === "push_failed", text);
  assert(!text.includes(SECRET) && !text.includes("PRIVATE KEY"), "Secret leaked");
});

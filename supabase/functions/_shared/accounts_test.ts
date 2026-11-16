import {
  adminHeaders,
  canManage,
  publishableKey,
  secretKey,
  validEmail,
  validPassword,
  validUuid,
} from "./accounts.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("the owner manages every role", () => {
  for (const target of ["owner", "worker", "teacher", "parent"]) {
    assert(canManage({ role: "owner", permissions: {} }, target, "add"), `owner/${target}`);
  }
  assert(!canManage({ role: "owner", permissions: {} }, "admin", "add"), "unknown role");
});

Deno.test("a worker manages teachers and parents only with the matching permission", () => {
  const teachersOnly = { role: "worker", permissions: { teachers: ["add"] } };
  assert(canManage(teachersOnly, "teacher", "add"), "teachers.add allows a teacher account");
  assert(!canManage(teachersOnly, "teacher", "edit"), "add is not edit");
  assert(!canManage(teachersOnly, "parent", "add"), "no students permission");
  assert(!canManage(teachersOnly, "worker", "add"), "workers are the owner's only");
  assert(!canManage(teachersOnly, "owner", "add"), "the owner account is the owner's only");

  const studentsEdit = { role: "worker", permissions: { students: ["edit"] } };
  assert(canManage(studentsEdit, "parent", "edit"), "students.edit allows a parent reset");
  assert(!canManage(studentsEdit, "parent", "add"), "edit is not add");
});

Deno.test("teachers and parents manage no accounts", () => {
  for (const role of ["teacher", "parent"]) {
    for (const target of ["teacher", "parent", "worker", "owner"]) {
      assert(!canManage({ role, permissions: { teachers: ["add"] } }, target, "add"), `${role}/${target}`);
    }
  }
});

Deno.test("input validators", () => {
  assert(validEmail("0550123456@school.local"), "generated email");
  assert(!validEmail("no-at-sign") && !validEmail("a@b") && !validEmail(5), "bad emails");
  assert(validPassword("12345678") && !validPassword("1234567") && !validPassword(null), "password length");
  assert(!validPassword("é".repeat(40)), "more than 72 bytes");
  assert(validUuid("0b1f6f0e-6f1d-4d5e-9c43-1c2c5b7a9e10") && !validUuid("not-a-uuid"), "uuid");
});

Deno.test("keys: the new JSON variables win and the legacy ones are the fallback", () => {
  const names = [
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const saved = names.map((n) => [n, Deno.env.get(n)] as const);
  try {
    for (const n of names) Deno.env.delete(n);
    assert(publishableKey() === undefined && secretKey() === undefined, "nothing configured");

    Deno.env.set("SUPABASE_ANON_KEY", "legacy-anon");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "legacy-service");
    assert(publishableKey() === "legacy-anon" && secretKey() === "legacy-service", "legacy fallback");

    Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ other: "sb_publishable_other" }));
    Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ default: "sb_secret_default", x: "y" }));
    assert(publishableKey() === "sb_publishable_other", "first value when there is no default");
    assert(secretKey() === "sb_secret_default", "the default secret key");

    Deno.env.set("SUPABASE_SECRET_KEYS", "not json");
    assert(secretKey() === "legacy-service", "bad JSON falls back");
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

Deno.test("admin headers: a JWT goes in both headers, a new key in apikey only", () => {
  const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig";
  const legacy = adminHeaders(jwt);
  assert(legacy.apikey === jwt && legacy.Authorization === `Bearer ${jwt}`, "legacy JWT");
  const fresh = adminHeaders("sb_secret_abc");
  assert(fresh.apikey === "sb_secret_abc" && !("Authorization" in fresh), "new secret key");
});

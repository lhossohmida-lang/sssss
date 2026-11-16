import {
  allowedTools,
  askModels,
  canTryNext,
  handle,
  modelChain,
  ProviderError,
  readCompletion,
  systemPrompt,
  toChatMessages,
  toChatTools,
} from "./index.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("worker tools follow server-side permission checks", () => {
  const tools = allowedTools("worker", {
    students: ["view"],
    attendance: ["view"],
  });
  if (!tools.has("search_students") || !tools.has("student_attendance")) {
    throw new Error("Expected tools for granted permissions");
  }
  if (tools.has("student_unpaid_dues") || tools.has("my_schedule")) {
    throw new Error("A worker received a tool without its required permission");
  }
});

Deno.test("teacher and parent tools stay within their role sets", () => {
  const teacher = allowedTools("teacher", {});
  const parent = allowedTools("parent", {});
  if (!teacher.has("propose_session_request") || teacher.has("student_unpaid_dues")) {
    throw new Error("Teacher tool scope is incorrect");
  }
  if (!parent.has("my_children") || parent.has("propose_session_request")) {
    throw new Error("Parent tool scope is incorrect");
  }
});

Deno.test("keeps tool calls and their results in OpenAI message form", () => {
  const messages = toChatMessages([
    { role: "user", content: "ابحث عن تلميذ" },
    {
      role: "assistant",
      tool_calls: [{
        id: "tool-1",
        function: { name: "search_students", arguments: "{\"query\":\"Ali\"}" },
      }],
    },
    { role: "tool", tool_call_id: "tool-1", content: "[]" },
  ]);
  const assistant = messages[1];
  const result = messages[2];
  if (assistant.role !== "assistant" || assistant.tool_calls?.length !== 1) {
    throw new Error("Assistant tool call was not preserved");
  }
  const call = assistant.tool_calls[0];
  assert(call.id === "tool-1" && call.type === "function", "Tool call ID or type changed");
  assert(call.function.name === "search_students", "Tool name changed");
  assert(call.function.arguments === "{\"query\":\"Ali\"}", "Arguments must be a JSON string");
  assert(assistant.content === null, "A tool-call turn without text has null content");
  if (result.role !== "tool" || result.tool_call_id !== "tool-1") {
    throw new Error("Tool result does not match its call");
  }
});

Deno.test("object arguments are normalised to a JSON string", () => {
  const messages = toChatMessages([
    { role: "user", content: "جدولي" },
    {
      role: "assistant",
      content: "سأبحث",
      tool_calls: [{ id: "a", function: { name: "my_schedule", arguments: { day: 1 } } }],
    },
  ]);
  const assistant = messages[1];
  if (assistant.role !== "assistant") throw new Error("Unexpected role");
  assert(assistant.tool_calls?.[0].function.arguments === "{\"day\":1}", "Arguments not normalised");
  assert(assistant.content === "سأبحث", "Assistant text was dropped");
});

Deno.test("rejects malformed conversations", () => {
  const bad: unknown[][] = [
    [],
    [{ role: "system", content: "تعليمات" }],
    [{ role: "user", content: "" }],
    [{ role: "assistant", tool_calls: [{ function: { name: "my_schedule", arguments: "{}" } }] }],
    [{ role: "assistant", tool_calls: [{ id: "x", function: { name: "my_schedule", arguments: "[]" } }] }],
    [{ role: "assistant", tool_calls: [] }],
    Array.from({ length: 49 }, () => ({ role: "user", content: "س" })),
  ];
  for (const input of bad) {
    let rejected = false;
    try {
      toChatMessages(input);
    } catch (error) {
      rejected = error instanceof TypeError;
    }
    assert(rejected, `Accepted ${JSON.stringify(input).slice(0, 80)}`);
  }
  let syntax = false;
  try {
    toChatMessages([{ role: "assistant", tool_calls: [{ id: "x", function: { name: "n", arguments: "{" } }] }]);
  } catch (error) {
    syntax = error instanceof SyntaxError;
  }
  assert(syntax, "Broken JSON arguments must be a SyntaxError (a 400)");
});

const schedule = {
  type: "function",
  function: {
    name: "my_schedule",
    description: "جدولي",
    parameters: { type: "object", properties: {}, additionalProperties: false },
  },
};

Deno.test("rejects tools the authenticated role cannot use", () => {
  let rejected = false;
  try {
    toChatTools(
      [{
        type: "function",
        function: {
          name: "student_unpaid_dues",
          description: "مستحقات التلميذ",
          parameters: { type: "object", properties: {}, additionalProperties: false },
        },
      }],
      allowedTools("teacher", {}),
    );
  } catch (error) {
    rejected = error instanceof Response && error.status === 403;
  }
  if (!rejected) throw new Error("A forbidden tool schema was accepted");
});

Deno.test("builds function tools for allowed names", () => {
  const tools = toChatTools([schedule], allowedTools("teacher", {}));
  assert(tools.length === 1 && tools[0].type === "function", "Tool not built");
  assert(tools[0].function.name === "my_schedule", "Tool name changed");
});

Deno.test("reads a text reply", () => {
  const reply = readCompletion(
    { choices: [{ message: { role: "assistant", content: "مرحباً" } }] },
    allowedTools("parent", {}),
  );
  assert(reply.content === "مرحباً" && reply.toolCalls.length === 0, "Text reply misread");
});

Deno.test("reads text split into content parts", () => {
  const reply = readCompletion(
    { choices: [{ message: { content: [{ type: "text", text: "أ" }, { type: "text", text: "ب" }] } }] },
    allowedTools("parent", {}),
  );
  assert(reply.content === "أب", "Content parts were not joined");
});

Deno.test("reads one tool call and parses its JSON arguments", () => {
  const reply = readCompletion(
    {
      choices: [{
        message: {
          content: null,
          tool_calls: [
            { id: "c1", type: "function", function: { name: "my_children", arguments: "{\"a\":1}" } },
            { id: "c2", type: "function", function: { name: "my_schedule", arguments: "{}" } },
          ],
        },
      }],
    },
    allowedTools("parent", {}),
  );
  assert(reply.toolCalls.length === 1, "Only one tool call per turn is allowed");
  const call = reply.toolCalls[0];
  assert(call.id === "c1" && call.name === "my_children" && call.arguments.a === 1, "Tool call misread");
});

Deno.test("ignores broken or forbidden tool calls and keeps the valid one", () => {
  const reply = readCompletion(
    {
      choices: [{
        message: {
          content: "",
          tool_calls: [
            { id: "x", function: { name: "student_unpaid_dues", arguments: "{}" } },
            { id: "y", function: { name: "my_children", arguments: "{broken" } },
            { id: "z", function: { name: "my_children", arguments: "" } },
          ],
        },
      }],
    },
    allowedTools("teacher", { x: 1 }).add("my_children"),
  );
  assert(reply.toolCalls.length === 1 && reply.toolCalls[0].id === "z", "Wrong call kept");
  assert(Object.keys(reply.toolCalls[0].arguments).length === 0, "Empty arguments become {}");
});

Deno.test("an unusable completion is an error", () => {
  const allowed = allowedTools("parent", {});
  for (const payload of [null, {}, { choices: [] }, { choices: [{}] }, { choices: [{ message: { content: "  " } }] }]) {
    let rejected = false;
    try {
      readCompletion(payload, allowed);
    } catch (error) {
      rejected = error instanceof TypeError;
    }
    assert(rejected, `Accepted ${JSON.stringify(payload)}`);
  }
});

Deno.test("the system prompt names the account role", () => {
  assert(systemPrompt("parent").includes("وليّ"), "Role label missing");
  assert(systemPrompt("owner").includes("صاحب المدرسة"), "Role label missing");
});

// ---- الدالة كاملة بخادم وهمي (Supabase والمزوّد)

const LLM_KEY = "sk-or-sentinel-key";
const ENV_NAMES = [
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEYS",
  "SUPABASE_ANON_KEY",
  "LLM_API_KEY",
  "LLM_MODEL",
  "LLM_BASE_URL",
];

type Provider = (url: URL, init: RequestInit) => Response | Promise<Response>;

async function withServer<T>(
  role: string,
  env: Record<string, string | undefined>,
  provider: Provider,
  run: () => Promise<T>,
): Promise<T> {
  const savedEnv = ENV_NAMES.map((name) => [name, Deno.env.get(name)] as const);
  const originalFetch = globalThis.fetch;
  for (const name of ENV_NAMES) Deno.env.delete(name);
  Deno.env.set("SUPABASE_URL", "https://abc.supabase.co");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEYS", JSON.stringify({ default: "sb_publishable_test" }));
  Deno.env.set("LLM_API_KEY", LLM_KEY);
  for (const [name, value] of Object.entries(env)) {
    if (value === undefined) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers);
    if (url.hostname === "abc.supabase.co") {
      if (url.pathname === "/auth/v1/user") {
        return Promise.resolve(
          headers.get("authorization") === "Bearer user-jwt"
            ? Response.json({ id: "caller-1" })
            : new Response("no", { status: 401 }),
        );
      }
      if (url.pathname === "/rest/v1/user_accounts") {
        return Promise.resolve(Response.json([{ id: "caller-1", role, entity_id: "e-1" }]));
      }
      return Promise.resolve(Response.json([{ permissions: "{}" }]));
    }
    return Promise.resolve(provider(url, init ?? {}));
  }) as typeof fetch;
  try {
    return await run();
  } finally {
    globalThis.fetch = originalFetch;
    for (const [name, value] of savedEnv) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

function ask(role: string, authorization = "Bearer user-jwt"): Request {
  return new Request("https://functions.test/assistant", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify({
      role,
      messages: [{ role: "user", content: "ما جدولي؟" }],
      tools: [schedule],
    }),
  });
}

const answer: Provider = () =>
  Response.json({
    choices: [{
      message: {
        role: "assistant",
        content: null,
        tool_calls: [{ id: "t1", type: "function", function: { name: "my_schedule", arguments: "{\"day\":2}" } }],
      },
    }],
  });

Deno.test("calls the model with the school's role, tools and the secret key", async () => {
  let seenUrl = "";
  let seenAuth = "";
  let sent: Record<string, unknown> = {};
  const result = await withServer("teacher", { LLM_MODEL: "google/gemma-4-31b-it:free" }, (url, init) => {
    seenUrl = url.toString();
    seenAuth = new Headers(init.headers).get("authorization") ?? "";
    sent = JSON.parse(String(init.body));
    return answer(url, init);
  }, async () => {
    const response = await handle(ask("teacher"));
    return { status: response.status, text: await response.text() };
  });
  assert(result.status === 200, `status ${result.status}`);
  const parsed = JSON.parse(result.text);
  assert(parsed.content === "" && parsed.toolCalls.length === 1, "Reply shape changed");
  assert(parsed.toolCalls[0].name === "my_schedule" && parsed.toolCalls[0].arguments.day === 2, "Call misread");
  assert(!result.text.includes(LLM_KEY), "The model key leaked into the reply");
  assert(seenUrl === "https://openrouter.ai/api/v1/chat/completions", `URL ${seenUrl}`);
  assert(seenAuth === `Bearer ${LLM_KEY}`, "The model key was not sent as a bearer token");
  assert(sent.model === "google/gemma-4-31b-it:free", "LLM_MODEL was ignored");
  assert(sent.parallel_tool_calls === false && sent.tool_choice === "auto", "Tool options missing");
  const messages = sent.messages as { role: string; content: string }[];
  assert(messages[0].role === "system" && messages[0].content.includes("أستاذ"), "System prompt missing");
  assert(messages[1].role === "user", "The user message must follow the system prompt");
});

Deno.test("uses OpenRouter and a free model when nothing is configured", async () => {
  let model = "";
  let url = "";
  await withServer("parent", {}, (u, init) => {
    url = u.toString();
    model = JSON.parse(String(init.body)).model;
    return Response.json({ choices: [{ message: { content: "أهلاً" } }] });
  }, () => handle(ask("parent")));
  assert(model === "openrouter/free" && url.startsWith("https://openrouter.ai/api/v1/"), `${url} ${model}`);
});

Deno.test("another provider is a base URL change", async () => {
  let url = "";
  await withServer("parent", { LLM_BASE_URL: "https://llm.example.com/v1/" }, (u) => {
    url = u.toString();
    return Response.json({ choices: [{ message: { content: "أهلاً" } }] });
  }, () => handle(ask("parent")));
  assert(url === "https://llm.example.com/v1/chat/completions", url);
});

Deno.test("provider failures map to clean status codes without details", async () => {
  const cases: [Provider, number, string][] = [
    [() => new Response("limit", { status: 429 }), 429, "model_rate_limited"],
    [() => new Response("boom", { status: 500 }), 502, "model_rejected"],
    [() => new Response("not json", { status: 200 }), 502, "model_bad_response"],
    [() => Response.json({ error: { message: "no credits" } }), 502, "model_bad_response"],
    [() => { throw new TypeError("network down"); }, 502, "model_unreachable"],
    [() => { throw new DOMException("slow", "TimeoutError"); }, 504, "model_timeout"],
  ];
  const original = console.error;
  const logged: string[] = [];
  console.error = (...args: unknown[]) => {
    logged.push(args.map(String).join(" "));
  };
  try {
    for (const [provider, status, code] of cases) {
      const result = await withServer("parent", {}, provider, async () => {
        const response = await handle(ask("parent"));
        return { status: response.status, text: await response.text() };
      });
      assert(result.status === status, `${code}: got ${result.status}`);
      assert(JSON.parse(result.text).error === code, `${code}: got ${result.text}`);
      assert(!result.text.includes(LLM_KEY), "The model key leaked into an error");
    }
  } finally {
    console.error = original;
  }
  const log = logged.join("\n");
  assert(!log.includes(LLM_KEY) && !log.includes("ما جدولي"), "A log line holds a key or a chat message");
});

Deno.test("is not configured without a model key or over plain http", async () => {
  for (const env of [{ LLM_API_KEY: undefined }, { LLM_BASE_URL: "http://insecure.example.com/v1" }]) {
    const response = await withServer("parent", env, answer, () => handle(ask("parent")));
    assert(response.status === 503, `status ${response.status}`);
  }
});

Deno.test("refuses a role that does not match the session and a missing session", async () => {
  assert((await withServer("parent", {}, answer, () => handle(ask("owner")))).status === 403, "role mismatch");
  assert((await withServer("parent", {}, answer, () => handle(ask("parent", "")))).status === 401, "no header");
  assert((await withServer("parent", {}, answer, () => handle(ask("parent", "Bearer old")))).status === 401, "bad session");
});

Deno.test("a forbidden tool in the request is refused before the model is called", async () => {
  let called = false;
  const request = new Request("https://functions.test/assistant", {
    method: "POST",
    headers: { authorization: "Bearer user-jwt", "content-type": "application/json" },
    body: JSON.stringify({
      role: "teacher",
      messages: [{ role: "user", content: "س" }],
      tools: [{ ...schedule, function: { ...schedule.function, name: "student_unpaid_dues" } }],
    }),
  });
  const response = await withServer("teacher", {}, (u, init) => {
    called = true;
    return answer(u, init);
  }, () => handle(request));
  assert(response.status === 403 && !called, `status ${response.status}, called ${called}`);
});

// ---- سلسلة بدائل النموذج

const OPENROUTER = "https://openrouter.ai/api/v1";

Deno.test("the model chain: default, free fallback, paid never falls to free", () => {
  assert(JSON.stringify(modelChain(undefined, OPENROUTER)) === '["openrouter/free"]', "default");
  assert(JSON.stringify(modelChain("  ", OPENROUTER)) === '["openrouter/free"]', "blank");
  assert(
    JSON.stringify(modelChain("google/gemma-4-31b-it:free", OPENROUTER)) ===
      '["google/gemma-4-31b-it:free","openrouter/free"]',
    "a free model must fall back to the free router",
  );
  assert(JSON.stringify(modelChain("openrouter/free", OPENROUTER)) === '["openrouter/free"]', "router twice");
  assert(
    JSON.stringify(modelChain("anthropic/claude-sonnet-5-5", OPENROUTER)) === '["anthropic/claude-sonnet-5-5"]',
    "a paid model fell back to a free one",
  );
  assert(
    JSON.stringify(modelChain("anthropic/claude-sonnet-5-5,vendor/x:free", OPENROUTER)) ===
      '["anthropic/claude-sonnet-5-5","vendor/x:free"]',
    "a chain holding a paid model got a free fallback appended",
  );
});

Deno.test("the model chain: dedupes, caps the list, and needs OpenRouter for the free router", () => {
  assert(
    JSON.stringify(modelChain("a:free, a:free ,b:free,c:free,d:free", OPENROUTER)) ===
      '["a:free","b:free","c:free","openrouter/free"]',
    "dedupe and cap",
  );
  assert(
    JSON.stringify(modelChain("a:free", "https://llm.example.com/v1")) === '["a:free"]',
    "another provider has no free router",
  );
  assert(JSON.stringify(modelChain("a:free", "not a url")) === '["a:free"]', "invalid base URL");
  assert(modelChain("x".repeat(200), OPENROUTER)[0] === "openrouter/free", "an oversize name is ignored");
});

Deno.test("only failures a different model can fix move on to the next model", () => {
  assert(canTryNext(new ProviderError(429, "model_rate_limited", 429)), "429");
  assert(canTryNext(new ProviderError(504, "model_timeout")), "timeout");
  assert(canTryNext(new ProviderError(502, "model_unreachable")), "unreachable");
  assert(canTryNext(new ProviderError(502, "model_bad_response")), "bad response");
  for (const upstream of [400, 404, 408, 500, 503]) {
    assert(canTryNext(new ProviderError(502, "model_rejected", upstream)), `upstream ${upstream}`);
  }
  for (const upstream of [401, 402, 403, undefined]) {
    assert(!canTryNext(new ProviderError(502, "model_rejected", upstream)), `upstream ${upstream}`);
  }
});

function withProvider<T>(provider: (model: string) => Response | Promise<Response>, run: () => Promise<T>) {
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  console.error = () => {};
  globalThis.fetch = ((_input: string | URL | Request, init?: RequestInit) => {
    const model = JSON.parse(String(init?.body)).model as string;
    return Promise.resolve(provider(model));
  }) as typeof fetch;
  return run().finally(() => {
    globalThis.fetch = originalFetch;
    console.error = originalError;
  });
}

const okReply = (text: string) => Response.json({ choices: [{ message: { content: text } }] });
const chain = (...models: string[]) => ({ baseUrl: OPENROUTER, apiKey: LLM_KEY, models });
const noTools = new Set<string>();
const hello: { role: "user"; content: string }[] = [{ role: "user", content: "سلام" }];

Deno.test("a rate-limited first model falls through to the next one and names the answerer", async () => {
  const asked: string[] = [];
  const reply = await withProvider((model) => {
    asked.push(model);
    return model === "a:free" ? new Response("slow down", { status: 429 }) : okReply("جاهز");
  }, () => askModels(chain("a:free", "openrouter/free"), "s", hello, [], noTools));
  assert(reply.content === "جاهز" && reply.model === "openrouter/free", `answered by ${reply.model}`);
  assert(asked.join() === "a:free,openrouter/free", `asked ${asked.join()}`);
});

Deno.test("the first model's answer ends the chain", async () => {
  const asked: string[] = [];
  const reply = await withProvider((model) => {
    asked.push(model);
    return okReply("أول");
  }, () => askModels(chain("a:free", "openrouter/free"), "s", hello, [], noTools));
  assert(reply.model === "a:free" && asked.length === 1, `asked ${asked.join()}`);
});

Deno.test("a key or credit failure stops the chain at once", async () => {
  for (const status of [401, 402, 403]) {
    const asked: string[] = [];
    let error: unknown;
    await withProvider((model) => {
      asked.push(model);
      return new Response("denied", { status });
    }, async () => {
      try {
        await askModels(chain("a:free", "openrouter/free"), "s", hello, [], noTools);
      } catch (e) {
        error = e;
      }
    });
    assert(error instanceof ProviderError && error.code === "model_rejected", `status ${status}`);
    assert(asked.length === 1, `status ${status} still asked ${asked.join()}`);
  }
});

Deno.test("when every model fails the last failure is reported", async () => {
  let error: unknown;
  const asked: string[] = [];
  await withProvider((model) => {
    asked.push(model);
    return model === "a:free" ? new Response("limit", { status: 429 }) : new Response("boom", { status: 503 });
  }, async () => {
    try {
      await askModels(chain("a:free", "openrouter/free"), "s", hello, [], noTools);
    } catch (e) {
      error = e;
    }
  });
  assert(asked.length === 2, `asked ${asked.join()}`);
  assert(error instanceof ProviderError && error.code === "model_rejected" && error.status === 502, "last error lost");
});

Deno.test("an exhausted time budget skips the remaining models", async () => {
  const asked: string[] = [];
  let error: unknown;
  await withProvider((model) => {
    asked.push(model);
    return new Response("limit", { status: 429 });
  }, async () => {
    try {
      await askModels(chain("a:free", "b:free", "openrouter/free"), "s", hello, [], noTools, 1);
    } catch (e) {
      error = e;
    }
  });
  assert(asked.length === 1, `asked ${asked.join()}`);
  assert(error instanceof ProviderError && error.status === 429, "the first failure should be reported");
});

Deno.test("the whole function uses the free router when a free model is overloaded", async () => {
  const asked: string[] = [];
  const result = await withServer("parent", { LLM_MODEL: "google/gemma-4-31b-it:free" }, (_u, init) => {
    const model = JSON.parse(String(init.body)).model as string;
    asked.push(model);
    return model === "openrouter/free" ? okReply("أهلاً") : new Response("limit", { status: 429 });
  }, async () => {
    const response = await handle(ask("parent"));
    return { status: response.status, body: await response.json() };
  });
  assert(result.status === 200 && result.body.content === "أهلاً", `status ${result.status}`);
  assert(result.body.model === "openrouter/free", `model ${result.body.model}`);
  assert(asked.join() === "google/gemma-4-31b-it:free,openrouter/free", `asked ${asked.join()}`);
});

Deno.test("the whole function never gives a paid model's conversation to a free one", async () => {
  const asked: string[] = [];
  const original = console.error;
  console.error = () => {};
  try {
    const result = await withServer("parent", { LLM_MODEL: "anthropic/claude-sonnet-5-5" }, (_u, init) => {
      asked.push(JSON.parse(String(init.body)).model as string);
      return new Response("limit", { status: 429 });
    }, async () => {
      const response = await handle(ask("parent"));
      return { status: response.status, body: await response.json() };
    });
    assert(result.status === 429 && result.body.error === "model_rate_limited", `status ${result.status}`);
  } finally {
    console.error = original;
  }
  assert(asked.join() === "anthropic/claude-sonnet-5-5", `asked ${asked.join()}`);
});

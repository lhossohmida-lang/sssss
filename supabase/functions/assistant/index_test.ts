import {
  allowedTools,
  toAnthropicMessages,
  toAnthropicTools,
} from "./index.ts";

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

Deno.test("converts tool calls and matching results to Anthropic message blocks", () => {
  const messages = toAnthropicMessages([
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
  if (assistant.role !== "assistant" || typeof assistant.content === "string") {
    throw new Error("Assistant tool use was not converted to content blocks");
  }
  const call = assistant.content.find((block) => block.type === "tool_use");
  if (call?.type !== "tool_use" || call.id !== "tool-1") {
    throw new Error("Tool call ID was not preserved");
  }
  if (result.role !== "user" || typeof result.content === "string") {
    throw new Error("Tool result was not converted to a user block");
  }
  const toolResult = result.content.find((block) => block.type === "tool_result");
  if (toolResult?.type !== "tool_result" || toolResult.tool_use_id !== call.id) {
    throw new Error("Tool result does not match its call");
  }
});

Deno.test("rejects tools the authenticated role cannot use", () => {
  let rejected = false;
  try {
    toAnthropicTools(
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

Deno.test("keeps every result in the same Anthropic tool turn", () => {
  const messages = toAnthropicMessages([
    { role: "user", content: "نفّذ طلبين" },
    {
      role: "assistant",
      tool_calls: [
        { id: "one", function: { name: "my_schedule", arguments: "{}" } },
        { id: "two", function: { name: "my_schedule", arguments: "{}" } },
      ],
    },
    { role: "tool", tool_call_id: "one", content: "[]", is_error: true },
    { role: "tool", tool_call_id: "two", content: "[]", is_error: true },
  ]);
  const assistant = messages[1];
  const results = messages[2];
  if (assistant.role !== "assistant" || typeof assistant.content === "string") {
    throw new Error("Assistant tool uses were not preserved");
  }
  if (results.role !== "user" || typeof results.content === "string") {
    throw new Error("Tool results were not grouped into a user message");
  }
  const toolResults = results.content.filter((block) => block.type === "tool_result");
  if (toolResults.length !== 2 || toolResults.some((block) => block.is_error !== true)) {
    throw new Error("Tool result IDs or error state were not preserved");
  }
});

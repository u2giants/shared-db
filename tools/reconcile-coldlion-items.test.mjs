import assert from "node:assert/strict";
import test from "node:test";
import { digest } from "./reconcile-coldlion-items.mjs";

test("identity fingerprints are order-independent and change with membership", () => {
  assert.equal(digest(["b", "a"]), digest(["a", "b"]));
  assert.notEqual(digest(["a", "b"]), digest(["a", "b", "c"]));
});

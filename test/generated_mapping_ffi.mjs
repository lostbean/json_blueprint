// synchronous test-only mapping event trace.
let events = "";
export function reset() {
  events = "";
}
export function mark(label) {
  events += label + ";";
}
export function trace() {
  return events;
}

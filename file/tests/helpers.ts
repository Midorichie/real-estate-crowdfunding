export function contractCall(contract: string, method: string, ...args: any[]) {
  return {
    contract,
    method,
    args,
    result: "mocked result",
  };
}

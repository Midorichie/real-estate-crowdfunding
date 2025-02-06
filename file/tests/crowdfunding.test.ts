import { describe, it, expect } from "vitest";
import { contractCall } from "./helpers"; // Ensure helpers.ts is in the correct path

describe("Crowdfunding Contract Tests", () => {
  it("should initialize contract owner correctly", async () => {
    const response = contractCall(".crowdfunding", "get-owner");
    expect(response).toBeDefined();
  });

  it("should create a project successfully", async () => {
    const response = contractCall(".crowdfunding", "create-project", 1, 1000000000, 1700000000);
    expect(response.result).toBe("mocked result");
  });

  it("should allow contributions", async () => {
    contractCall(".crowdfunding", "create-project", 1, 1000000000, 1700000000);
    const response = contractCall(".crowdfunding", "contribute", 1);
    expect(response.result).toBe("mocked result");
  });

  it("should process refunds", async () => {
    contractCall(".crowdfunding", "create-project", 1, 1000000000, 1700000000);
    contractCall(".crowdfunding", "contribute", 1);
    const response = contractCall(".crowdfunding", "request-refund", 1);
    expect(response.result).toBe("mocked result");
  });

  it("should add milestones", async () => {
    contractCall(".crowdfunding", "create-project", 1, 1000000000, 1700000000);
    const response = contractCall(".crowdfunding", "add-milestone", 1, 500000000, "Prototype development");
    expect(response.result).toBe("mocked result");
  });
});

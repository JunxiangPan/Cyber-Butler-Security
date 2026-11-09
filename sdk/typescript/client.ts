/**
 * CBS Broker TypeScript client.
 *
 * Loopback-only. The browser's fetch is not used for the token path; callers
 * supply the token explicitly or read it from their own secure store.
 */

export type CbsStatus = "pending" | "approved" | "denied" | "expired" | "unknown";

export interface CbsApprovalStatus {
  ok: boolean;
  status: CbsStatus;
  challenge_id: string;
  approval_only: boolean;
  scoped_token?: string;
  scoped_expires_in?: number;
  scoped_root?: string;
  error?: string;
}

export class CbsClient {
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly timeoutMs: number;

  constructor(baseUrl: string, token: string, timeoutMs = 10_000) {
    if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(baseUrl)) {
      throw new Error("CBS Broker client only accepts loopback URLs");
    }
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.token = token;
    this.timeoutMs = timeoutMs;
  }

  private async call(path: string, init: RequestInit = {}): Promise<any> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(this.baseUrl + path, {
        ...init,
        signal: controller.signal,
        headers: {
          "X-Broker-Token": this.token,
          "Accept": "application/json",
          ...(init.headers ?? {}),
        },
      });
      const body = await response.json();
      if (!response.ok) {
        throw new Error(`CBS Broker error ${response.status}: ${body.error ?? JSON.stringify(body)}`);
      }
      return body;
    } finally {
      clearTimeout(timer);
    }
  }

  requestApproval(action: string, target: string, reason = ""): Promise<any> {
    return this.call("/request", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ action, target, reason, approval_only: true }),
    });
  }

  status(challengeId: string): Promise<CbsApprovalStatus> {
    return this.call("/api/request_approval/status?id=" + encodeURIComponent(challengeId));
  }

  verify(challengeId: string, code: string): Promise<any> {
    return this.call("/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ id: challengeId, code }),
    });
  }

  async waitForApproval(challengeId: string, timeoutMs = 180_000, intervalMs = 2_000): Promise<CbsApprovalStatus> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const body = await this.status(challengeId);
      if (body.status !== "pending") return body;
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
    throw new Error(`approval did not leave pending within ${timeoutMs}ms`);
  }
}

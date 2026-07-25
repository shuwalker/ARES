import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const read = (relative: string) =>
  readFileSync(fileURLToPath(new URL(relative, import.meta.url)), "utf8");

const indexCss = read("./index.css");
const backdropCss = read("./styles/island-backdrop.css");
const shell = read("./components/command-center/CommandCenterShell.tsx");

/**
 * The command-center chrome was hardcoded as inline hex values. Phase 2 of
 * docs/ui/glassmorphism-plan.md lifted the surface and border colors into tokens
 * so the island backdrop can make them translucent in one place.
 *
 * The whole approach depends on the tokens being *exactly* the old values: the
 * shell palette is warm-neutral and does not match the cool `--card` scale, so
 * folding it into the generic tokens would visibly recolor the workbench.
 */
describe("command-center shell tokens", () => {
  it("preserves the original chrome colors byte-for-byte", () => {
    const expected: Record<string, string> = {
      "--shell-deep": "#111210",
      "--shell": "#151614",
      "--shell-raised": "#1b1c1a",
      "--edge": "#343631",
      "--edge-strong": "#4a4d45",
      "--edge-emphasis": "#71736b",
    };
    for (const [token, hex] of Object.entries(expected)) {
      expect(indexCss).toContain(`${token}: ${hex};`);
    }
  });

  it("registers each token in the Tailwind color namespace so utilities exist", () => {
    // Without these, `bg-shell` compiles to nothing and the surface renders
    // transparent rather than dark — a silent, total loss of shell chrome.
    for (const name of ["shell", "shell-deep", "shell-raised", "edge", "edge-strong", "edge-emphasis"]) {
      expect(indexCss).toContain(`--color-${name}: var(--${name});`);
    }
  });

  it("leaves no raw surface or border hex in the shell", () => {
    const rawSurfaces = shell.match(/(?:bg|border)-\[#[0-9a-fA-F]+\]/g) ?? [];
    expect(rawSurfaces).toEqual([]);
  });

  it("keeps the text palette untouched — only surfaces need translucency", () => {
    // Text colors are intentionally still literal. Converting them buys nothing
    // for glassmorphism and would balloon the diff across 300+ usages.
    expect(shell).toContain("text-[#ecebe4]");
  });

  it("re-declares every shell surface token under the backdrop gate", () => {
    for (const token of ["--shell-deep", "--shell", "--shell-raised", "--edge"]) {
      expect(backdropCss).toContain(`${token}: color-mix(`);
    }
  });
});

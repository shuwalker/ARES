import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const read = (relative: string) =>
  readFileSync(fileURLToPath(new URL(relative, import.meta.url)), "utf8");

const indexCss = read("./index.css");
const backdropCss = read("./styles/island-backdrop.css");
const shell = read("./components/command-center/CommandCenterShell.tsx");
const deck = read("./components/command-center/ControlDeck.tsx");

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
      "--shell-elevated": "#20211f",
      "--shell-hover": "#292b28",
      "--overlay": "#1a1c24",
      "--overlay-hover": "#252836",
      "--overlay-inset": "#161824",
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
    for (const name of [
      "shell",
      "shell-deep",
      "shell-raised",
      "shell-elevated",
      "shell-hover",
      "edge",
      "edge-strong",
      "edge-emphasis",
      "overlay",
      "overlay-hover",
      "overlay-inset",
    ]) {
      expect(indexCss).toContain(`--color-${name}: var(--${name});`);
    }
  });

  it("leaves no raw surface hex in the shell or the control deck", () => {
    expect(shell.match(/(?:bg|border)-\[#[0-9a-fA-F]+\]/g) ?? []).toEqual([]);
    // The deck keeps literal accent and status colors (blues, red, amber) and a
    // few one-off borders; only the surfaces it paints large areas with had to
    // become tokens.
    expect(deck.match(/\bbg-\[#(?:111210|151614|1b1c1a|20211f|292b28|1a1c24|252836|161824)\]/gi) ?? []).toEqual([]);
  });

  it("keeps floating overlays opaque under the backdrop", () => {
    // Menus, toasts, and dialogs float over arbitrary content. If these ever
    // gain a color-mix override they become unreadable, not pretty.
    for (const token of ["--overlay", "--overlay-hover", "--overlay-inset"]) {
      expect(backdropCss).not.toContain(`${token}: color-mix(`);
    }
  });

  it("keeps the text palette untouched — only surfaces need translucency", () => {
    // Text colors are intentionally still literal. Converting them buys nothing
    // for glassmorphism and would balloon the diff across 300+ usages.
    expect(shell).toContain("text-[#ecebe4]");
  });

  it("re-declares every shell surface token under the backdrop gate", () => {
    for (const token of [
      "--shell-deep",
      "--shell",
      "--shell-raised",
      "--shell-elevated",
      "--shell-hover",
      "--edge",
    ]) {
      expect(backdropCss).toContain(`${token}: color-mix(`);
    }
  });
});

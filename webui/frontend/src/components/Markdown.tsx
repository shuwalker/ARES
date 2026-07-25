import { useMemo, type ReactNode } from "react";

// Lightweight markdown renderer for LLM output.
// Handles: code blocks, inline code, bold, italic, headers, links, lists, horizontal rules.
// Optimized for typical assistant message patterns, not full CommonMark.

export function Markdown({
  content,
  highlightTerms,
  streaming,
  className = "text-sm leading-relaxed",
}: {
  content: string;
  highlightTerms?: string[];
  streaming?: boolean;
  className?: string;
}) {
  const blocks = useMemo(() => parseBlocks(content), [content]);
  const caret = streaming ? <StreamingCaret /> : null;

  return (
    <div className={className}>
      {blocks.map((block, i) => (
        <Block
          key={i}
          block={block}
          highlightTerms={highlightTerms}
          caret={caret && i === blocks.length - 1 ? caret : null}
        />
      ))}
      {blocks.length === 0 && caret}
    </div>
  );
}

function StreamingCaret() {
  return (
    <span
      aria-hidden
      className="inline-block w-[0.5em] h-[1em] ml-0.5 align-[-0.15em] bg-[#ECEBE4]/50 animate-pulse"
    />
  );
}

type BlockNode =
  | { type: "code"; lang: string; content: string }
  | { type: "heading"; level: number; content: string }
  | { type: "hr" }
  | { type: "list"; ordered: boolean; items: string[] }
  | { type: "paragraph"; content: string };

function parseBlocks(text: string): BlockNode[] {
  const lines = text.split("\n");
  const blocks: BlockNode[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    const fenceMatch = line.match(/^```(\w*)/);
    if (fenceMatch) {
      const lang = fenceMatch[1] || "";
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith("```")) {
        codeLines.push(lines[i]);
        i++;
      }
      i++;
      blocks.push({ type: "code", lang, content: codeLines.join("\n") });
      continue;
    }

    const headingMatch = line.match(/^(#{1,4})\s+(.+)/);
    if (headingMatch) {
      blocks.push({ type: "heading", level: headingMatch[1].length, content: headingMatch[2] });
      i++;
      continue;
    }

    if (/^[-*_]{3,}\s*$/.test(line)) {
      blocks.push({ type: "hr" });
      i++;
      continue;
    }

    if (/^[-*+]\s/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^[-*+]\s/.test(lines[i])) {
        items.push(lines[i].replace(/^[-*+]\s/, ""));
        i++;
      }
      blocks.push({ type: "list", ordered: false, items });
      continue;
    }

    if (/^\d+[.)]\s/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\d+[.)]\s/.test(lines[i])) {
        items.push(lines[i].replace(/^\d+[.)]\s/, ""));
        i++;
      }
      blocks.push({ type: "list", ordered: true, items });
      continue;
    }

    if (line.trim() === "") {
      i++;
      continue;
    }

    const paraLines: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !lines[i].match(/^```/) &&
      !lines[i].match(/^#{1,4}\s/) &&
      !lines[i].match(/^[-*+]\s/) &&
      !lines[i].match(/^\d+[.)]\s/) &&
      !lines[i].match(/^[-*_]{3,}\s*$/)
    ) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      blocks.push({ type: "paragraph", content: paraLines.join("\n") });
    }
  }

  return blocks;
}

function Block({
  block,
  highlightTerms,
  caret,
}: {
  block: BlockNode;
  highlightTerms?: string[];
  caret?: ReactNode;
}) {
  switch (block.type) {
    case "code":
      return (
        <pre className="rounded-md border border-[#343631] bg-[#111210] px-3 py-2.5 text-xs font-mono leading-relaxed overflow-x-auto">
          <code className="text-[#ECEBE4]">
            {block.content}
            {caret}
          </code>
        </pre>
      );

    case "heading": {
      const Tag = `h${Math.min(block.level, 4)}` as "h1" | "h2" | "h3" | "h4";
      const sizes: Record<string, string> = {
        h1: "text-base font-bold text-[#FAF9F3]",
        h2: "text-sm font-bold text-[#FAF9F3]",
        h3: "text-sm font-semibold text-[#ECEBE4]",
        h4: "text-sm font-medium text-[#D7D6CE]",
      };
      return (
        <Tag className={`${sizes[Tag]} mt-1`}>
          <InlineContent text={block.content} highlightTerms={highlightTerms} />
          {caret}
        </Tag>
      );
    }

    case "hr":
      return (
        <>
          <hr className="border-[#343631]" />
          {caret}
        </>
      );

    case "list": {
      const Tag = block.ordered ? "ol" : "ul";
      const last = block.items.length - 1;
      return (
        <Tag className={`space-y-0.5 ${block.ordered ? "list-decimal" : "list-disc"} pl-5 text-[#ECEBE4]`}>
          {block.items.map((item, i) => (
            <li key={i}>
              <InlineContent text={item} highlightTerms={highlightTerms} />
              {i === last ? caret : null}
            </li>
          ))}
        </Tag>
      );
    }

    case "paragraph":
      return (
        <p className="text-[#ECEBE4]">
          <InlineContent text={block.content} highlightTerms={highlightTerms} />
          {caret}
        </p>
      );
  }
}

type InlineNode =
  | { type: "text"; content: string }
  | { type: "code"; content: string }
  | { type: "bold"; content: string }
  | { type: "italic"; content: string }
  | { type: "link"; text: string; href: string }
  | { type: "br" };

function parseInline(text: string): InlineNode[] {
  const nodes: InlineNode[] = [];
  const pattern =
    /(`[^`]+`)|(\[([^\]]+)\]\(([^)]+)\))|(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(\bhttps?:\/\/[^\s<>)\]]+)|(\n)/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > lastIndex) {
      nodes.push({ type: "text", content: text.slice(lastIndex, match.index) });
    }

    if (match[1]) {
      nodes.push({ type: "code", content: match[1].slice(1, -1) });
    } else if (match[2]) {
      nodes.push({ type: "link", text: match[3], href: match[4] });
    } else if (match[5]) {
      nodes.push({ type: "bold", content: match[6] });
    } else if (match[7]) {
      nodes.push({ type: "italic", content: match[8] });
    } else if (match[9]) {
      nodes.push({ type: "link", text: match[9], href: match[9] });
    } else if (match[10]) {
      nodes.push({ type: "br" });
    }

    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < text.length) {
    nodes.push({ type: "text", content: text.slice(lastIndex) });
  }

  return nodes;
}

function InlineContent({ text, highlightTerms }: { text: string; highlightTerms?: string[] }) {
  const nodes = useMemo(() => parseInline(text), [text]);

  return (
    <>
      {nodes.map((node, i) => {
        switch (node.type) {
          case "text":
            return <HighlightedText key={i} text={node.content} terms={highlightTerms} />;
          case "code":
            return (
              <code key={i} className="rounded bg-[#20211F] px-1.5 py-0.5 text-xs font-mono text-[#D7D6CE]">
                {node.content}
              </code>
            );
          case "bold":
            return (
              <strong key={i} className="font-semibold text-[#FAF9F3]">
                <HighlightedText text={node.content} terms={highlightTerms} />
              </strong>
            );
          case "italic":
            return (
              <em key={i}>
                <HighlightedText text={node.content} terms={highlightTerms} />
              </em>
            );
          case "link": {
            const href = node.href.trim();
            if (!/^(https?:|mailto:)/i.test(href)) {
              return <HighlightedText key={i} text={node.text} terms={highlightTerms} />;
            }
            return (
              <a
                key={i}
                href={href}
                target="_blank"
                rel="noreferrer"
                className="text-[#D7D6CE] underline underline-offset-2 decoration-[#D7D6CE]/30 hover:decoration-[#D7D6CE]/60 transition-colors"
              >
                {node.text}
              </a>
            );
          }
          case "br":
            return <br key={i} />;
        }
      })}
    </>
  );
}

function HighlightedText({ text, terms }: { text: string; terms?: string[] }) {
  if (!terms || terms.length === 0) return <>{text}</>;
  const escaped = terms.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$\u0026"));
  const regex = new RegExp(`(${escaped.join("|")})`, "gi");
  const parts = text.split(regex);

  return (
    <>
      {parts.map((part, i) =>
        regex.test(part) ? (
          <mark key={i} className="bg-[#D7D6CE]/20 text-[#FAF9F3] px-0.5">{part}</mark>
        ) : (
          <span key={i}>{part}</span>
        )
      )}
    </>
  );
}

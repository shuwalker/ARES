/**
 * @file Tip.tsx
 * @description A reusable React component that displays a tooltip with custom content when the user hovers over the wrapped children.
 * Tooltip follows the cursor position and uses a portal to avoid clipping by parent overflow or screen edges.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

import { useState, useRef, useCallback } from "react";
import { createPortal } from "react-dom";

interface TipProps {
  raw?: string;
  children: React.ReactNode;
  /** Override max width of tooltip (px). Default 320 */
  maxWidth?: number;
  /** Render wrapper as block-level div instead of inline span. Use when wrapping full-width elements. */
  block?: boolean;
}

export function Tip({ raw, children, maxWidth = 320, block = false }: TipProps) {
  const [show, setShow] = useState(false);
  const [pos, setPos] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const tipRef = useRef<HTMLDivElement>(null);

  const updatePos = useCallback((e: React.MouseEvent) => {
    setPos({ x: e.clientX, y: e.clientY });
  }, []);

  if (!raw) return <>{children}</>;

  const Wrapper = block ? "div" : "span";
  const wrapperClass = block ? "cursor-default" : "relative inline-block cursor-default";

  // Compute tooltip placement avoiding screen edges
  let tipStyle: React.CSSProperties = {
    position: "fixed",
    zIndex: 99999,
    maxWidth,
    visibility: "hidden",
  };
  if (show) {
    const tipW = tipRef.current?.offsetWidth ?? 200;
    const tipH = tipRef.current?.offsetHeight ?? 32;
    const vw = document.documentElement.clientWidth;
    const vh = window.innerHeight;
    const pad = 12;

    // Default: below-right of cursor
    let left = pos.x + pad;
    let top = pos.y + pad;

    // If goes off right edge, flip to left of cursor
    if (left + tipW > vw - pad) {
      left = pos.x - tipW - pad;
    }
    // If goes off left edge, clamp
    if (left < pad) left = pad;

    // If goes off bottom, show above cursor
    if (top + tipH > vh - pad) {
      top = pos.y - tipH - pad;
    }
    // If goes off top, clamp
    if (top < pad) top = pad;

    tipStyle = { position: "fixed", left, top, zIndex: 99999, maxWidth, visibility: "visible" };
  }

  return (
    <Wrapper
      className={wrapperClass}
      onMouseEnter={(e: React.MouseEvent) => {
        setShow(true);
        updatePos(e);
      }}
      onMouseMove={updatePos}
      onMouseLeave={() => setShow(false)}
    >
      {children}
      {show &&
        createPortal(
          <div
            ref={tipRef}
            style={tipStyle}
            className="px-2.5 py-1.5 text-[11px] leading-relaxed font-mono text-gray-100 bg-[#12121f] border border-[#2a2a4a] rounded-lg shadow-xl pointer-events-none whitespace-pre-wrap break-words"
          >
            {raw}
          </div>,
          document.body
        )}
    </Wrapper>
  );
}

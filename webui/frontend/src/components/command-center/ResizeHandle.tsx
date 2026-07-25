import { GripVertical } from "lucide-react";
import { Separator } from "react-resizable-panels";

export function ResizeHandle({ id }: { id: string }) {
  return (
    <Separator
      id={id}
      className="group relative z-10 w-px bg-[#343631] outline-none transition-colors hover:bg-[#71736b] focus-visible:bg-[#d7d6ce]"
    >
      <span className="pointer-events-none absolute left-1/2 top-1/2 grid h-8 w-3 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-sm border border-[#343631] bg-[#1b1c1a] opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
        <GripVertical className="size-2.5 text-[#a7a79d]" aria-hidden="true" />
      </span>
    </Separator>
  );
}

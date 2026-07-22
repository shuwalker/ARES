import { BookOpen, Highlighter, Search, ScrollText } from "lucide-react";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

/**
 * Library surface — personal Alexandria.
 * Knowledge owned by the user (not Self, not memory infrastructure).
 */
export function LibraryPage() {
  return (
    <SurfaceShell
      title="Library"
      description="Your personal Alexandria — books, PDFs, notes, highlights, education, history, and long-term knowledge."
    >
      <SurfaceNote>
        Library is knowledge you own and preserve. Self is knowledge about you. System only configures
        how knowledge is indexed (memory infrastructure) — content lives here.
      </SurfaceNote>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <BookOpen className="size-4 text-primary" />
            Wings of the Library
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm text-muted-foreground sm:grid-cols-2">
          <p><span className="font-medium text-foreground">Reference</span> — books, PDFs, citations</p>
          <p><span className="font-medium text-foreground">Notes</span> — highlights, Zettel-style slips</p>
          <p><span className="font-medium text-foreground">Education</span> — courses, curricula, review</p>
          <p><span className="font-medium text-foreground">World</span> — history, philosophy, culture</p>
        </CardContent>
      </Card>

      <SurfaceLinkGrid
        links={[
          {
            to: "/collections",
            label: "Collections",
            description: "Connect an Obsidian vault, local folder, or network drive.",
            icon: ScrollText,
          },
          {
            to: "/search",
            label: "Search knowledge",
            description: "Find across sessions and indexed material.",
            icon: Search,
          },
          {
            to: "/system",
            label: "Memory infrastructure",
            description: "Configure indexing & RAG in System — not here.",
            icon: Highlighter,
          },
        ]}
      />

      <p className="text-xs text-muted-foreground">
        Full Alexandria (import shelves, PDF library, knowledge graph) builds on this shell. Collections
        and provenance APIs land next; the domain boundary is fixed now.
      </p>
    </SurfaceShell>
  );
}

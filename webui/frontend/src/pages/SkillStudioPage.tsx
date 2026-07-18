import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  FileCode2,
  LoaderCircle,
  RotateCw,
  Save,
} from "lucide-react";
import { useSearchParams, useNavigate } from "react-router-dom";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SkillDetail {
  name: string;
  content: string;
  category: string;
  disabled: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function extractFrontmatterField(content: string, field: string): string {
  const match = content.match(new RegExp(`^${field}:\\s*(.+)$`, "m"));
  return match ? match[1].trim().replace(/^["']|["']$/g, "") : "";
}

function buildSkillYaml(name: string, category: string, description: string, trigger: string, instructions: string): string {
  const lines: string[] = ["---"];
  if (name) lines.push(`name: "${name}"`);
  if (category) lines.push(`category: "${category}"`);
  if (description) lines.push(`description: "${description}"`);
  if (trigger) lines.push(`trigger: "${trigger}"`);
  lines.push("---");
  lines.push("");
  if (instructions) lines.push(instructions);
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Skill Studio Page
// ---------------------------------------------------------------------------

export default function SkillStudioPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const editName = searchParams.get("name") ?? "";
  const isEditing = Boolean(editName);

  // ---- Form state ----
  const [name, setName] = useState("");
  const [category, setCategory] = useState("");
  const [content, setContent] = useState("");
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(isEditing);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // ---- Load skill for editing ----

  useEffect(() => {
    if (!editName) return;
    let active = true;
    setLoading(true);
    setError(null);
    aresApi
      .skillsGet(editName)
      .then((data: SkillDetail) => {
        if (!active) return;
        setName(data.name);
        setCategory(data.category || "");
        setContent(data.content || "");
      })
      .catch((err) => {
        if (active) setError(readableError(err, "Failed to load skill."));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [editName]);

  // ---- Save handler ----

  const handleSave = useCallback(async () => {
    const trimmedName = name.trim();
    if (!trimmedName) {
      setError("Skill name is required.");
      return;
    }
    setSaving(true);
    setError(null);
    setSuccess(null);
    try {
      await aresApi.skillsSave(trimmedName, content, category.trim() || undefined);
      setSuccess("Skill saved successfully.");
      if (!isEditing) {
        // After creating, switch to edit mode so we don't create duplicates
        navigate(`/skills/studio?name=${encodeURIComponent(trimmedName)}`, { replace: true });
      }
    } catch (err) {
      setError(readableError(err, "Failed to save skill."));
    } finally {
      setSaving(false);
    }
  }, [name, category, content, isEditing, navigate]);

  // ---- Load template ----

  const loadTemplate = useCallback(() => {
    setName("my-new-skill");
    setCategory("productivity");
    setContent(buildSkillYaml("my-new-skill", "productivity", "A brief description of what this skill does.", "When the user asks about X", "Step-by-step instructions for the AI to follow:\n\n1. First, do this.\n2. Then, do that.\n3. Finally, present the result.\n\nPitfalls:\n- Watch out for edge case Y.\n- Don't forget to handle Z."));
  }, []);

  // ---- Render ----

  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Skill Studio" description="Loading skill…" />
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading skill definition…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title={isEditing ? `Edit: ${editName}` : "Skill Studio"}
        description={
          isEditing
            ? "Edit the YAML definition for this skill."
            : "Create a new skill by defining its YAML frontmatter and instructions."
        }
        action={
          <div className="flex gap-2">
            {!isEditing && (
              <Button variant="outline" size="sm" onClick={loadTemplate}>
                <FileCode2 className="size-4" />
                Load Template
              </Button>
            )}
            <Button
              size="sm"
              disabled={saving || !name.trim()}
              onClick={() => void handleSave()}
            >
              {saving ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}
              {saving ? "Saving…" : "Save Skill"}
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <span className="inline-flex items-center gap-2">
            <AlertCircle className="size-4" />
            {error}
          </span>
        </div>
      )}

      {success && (
        <div className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-700 dark:text-emerald-300">
          {success}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[280px_1fr]">
        {/* Metadata panel */}
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="skill-name">Skill Name</Label>
            <Input
              id="skill-name"
              placeholder="e.g. my-custom-skill"
              value={name}
              onChange={(e) => setName(e.target.value)}
              disabled={isEditing}
              className={isEditing ? "opacity-60" : ""}
            />
            {isEditing && (
              <p className="text-xs text-muted-foreground">
                Skill name cannot be changed after creation.
              </p>
            )}
          </div>
          <div className="grid gap-2">
            <Label htmlFor="skill-category">Category</Label>
            <Input
              id="skill-category"
              placeholder="e.g. productivity, devops"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Optional category for organizing skills.
            </p>
          </div>

          {/* Quick reference */}
          <div className="rounded-lg border border-border bg-muted/30 p-3">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              YAML Frontmatter
            </h3>
            <div className="text-xs text-muted-foreground space-y-1">
              <p>
                <code className="rounded bg-muted px-1 font-mono">---</code> marks the start/end of frontmatter.
              </p>
              <p>
                Supported fields: <code className="rounded bg-muted px-1 font-mono">name</code>,{" "}
                <code className="rounded bg-muted px-1 font-mono">category</code>,{" "}
                <code className="rounded bg-muted px-1 font-mono">description</code>,{" "}
                <code className="rounded bg-muted px-1 font-mono">trigger</code>.
              </p>
              <p>
                Everything after the closing <code className="rounded bg-muted px-1 font-mono">---</code> is the skill body (Markdown instructions).
              </p>
            </div>
          </div>

          {/* Parsed preview */}
          {content && (
            <div className="rounded-lg border border-border bg-muted/30 p-3">
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Parsed Preview
              </h3>
              <div className="space-y-1.5 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Name</span>
                  <span className="font-medium">{extractFrontmatterField(content, "name") || "—"}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Category</span>
                  <Badge variant="outline">
                    {extractFrontmatterField(content, "category") || "none"}
                  </Badge>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Trigger</span>
                  <span className="truncate max-w-[160px] text-xs">
                    {extractFrontmatterField(content, "trigger") || "—"}
                  </span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Editor */}
        <div className="grid gap-2">
          <div className="flex items-center justify-between">
            <Label htmlFor="skill-content" className="text-base font-semibold">
              Skill Content
            </Label>
            <div className="flex gap-1.5">
              <Button
                variant="outline"
                size="xs"
                onClick={() => {
                  navigator.clipboard.writeText(content).catch(() => undefined);
                }}
                disabled={!content}
              >
                Copy
              </Button>
              <Button
                variant="outline"
                size="xs"
                onClick={() => setContent("")}
                disabled={!content}
              >
                Clear
              </Button>
            </div>
          </div>
          <Textarea
            id="skill-content"
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={`---\nname: "my-skill"\ncategory: "productivity"\ndescription: "What this skill does"\ntrigger: "When the user asks about X"\n---\n\nStep-by-step instructions for the AI...`}
            className="min-h-[400px] font-mono text-sm leading-relaxed"
          />
          <p className="text-xs text-muted-foreground">
            Edit the full skill YAML above. Include frontmatter between <code>---</code> delimiters, followed by the skill body in Markdown.
          </p>
        </div>
      </div>
    </div>
  );
}
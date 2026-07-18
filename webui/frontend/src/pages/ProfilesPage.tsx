import { useCallback, useEffect, useState } from "react";
import {
  Check,
  ChevronDown,
  Copy,
  Cpu,
  MoreVertical,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
  User,
} from "lucide-react";
import { apiFetch, readableError } from "@/shared/api-client";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

const PROFILE_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

interface ProfileInfo {
  name: string;
  is_default: boolean;
  description?: string;
  model?: string;
  provider?: string;
  skills_count?: number;
  path?: string;
}

interface ModelChoice {
  provider: string;
  model: string;
  label: string;
}

export default function ProfilesPage() {
  const [profiles, setProfiles] = useState<ProfileInfo[]>([]);
  const [activeProfile, setActiveProfile] = useState<string>("default");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Create dialog
  const [createOpen, setCreateOpen] = useState(false);
  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [newCloneFrom, setNewCloneFrom] = useState<string>("");
  const [creating, setCreating] = useState(false);

  // Delete dialog
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  // Switch active
  const [settingActive, setSettingActive] = useState<string | null>(null);

  // Rename inline
  const [renamingFrom, setRenamingFrom] = useState<string | null>(null);
  const [renameTo, setRenameTo] = useState("");
  const [renameSaving, setRenameSaving] = useState(false);

  // Model editing inline
  const [modelChoices, setModelChoices] = useState<ModelChoice[]>([]);
  const [editModelFor, setEditModelFor] = useState<string | null>(null);
  const [modelChoice, setModelChoice] = useState("");
  const [modelSaving, setModelSaving] = useState(false);

  // Clone dialog
  const [cloneOpen, setCloneOpen] = useState(false);
  const [cloneSource, setCloneSource] = useState<string>("");
  const [cloneName, setCloneName] = useState("");
  const [cloneDescription, setCloneDescription] = useState("");
  const [cloning, setCloning] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [profRes, activeRes] = await Promise.allSettled([
        apiFetch<{ profiles: ProfileInfo[] }>("/api/profiles"),
        apiFetch<{ active: string }>("/api/profiles/active").catch(() => ({
          active: "default",
        })),
      ]);
      if (profRes.status === "fulfilled")
        setProfiles(profRes.value.profiles ?? []);
      if (activeRes.status === "fulfilled")
        setActiveProfile(activeRes.value.active ?? "default");
    } catch (e) {
      setError(readableError(e, "Failed to load profiles"));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const loadModels = useCallback(async () => {
    try {
      const res = await apiFetch<{
        providers: { slug: string; name: string; models: string[] }[];
      }>("/api/models/options");
      const flat: ModelChoice[] = [];
      for (const prov of res.providers ?? []) {
        for (const m of prov.models ?? []) {
          flat.push({
            provider: prov.slug,
            model: m,
            label: `${prov.name} · ${m}`,
          });
        }
      }
      setModelChoices(flat);
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    if (editModelFor) loadModels();
  }, [editModelFor, loadModels]);

  // ── Handlers ────────────────────────────────────────────────────────

  const handleCreate = async () => {
    const name = newName.trim();
    if (!name || !PROFILE_NAME_RE.test(name)) {
      setError(
        "Invalid profile name. Use lowercase letters, numbers, hyphens, underscores.",
      );
      return;
    }
    setCreating(true);
    setError(null);
    try {
      await apiFetch("/api/profiles", {
        method: "POST",
        body: JSON.stringify({
          name,
          description: newDescription.trim() || undefined,
          clone_from: newCloneFrom || undefined,
        }),
      });
      setCreateOpen(false);
      setNewName("");
      setNewDescription("");
      setNewCloneFrom("");
      load();
    } catch (e) {
      setError(readableError(e, "Failed to create profile"));
    } finally {
      setCreating(false);
    }
  };

  const handleSetActive = async (name: string) => {
    setSettingActive(name);
    setError(null);
    try {
      await apiFetch("/api/profiles/active", {
        method: "PUT",
        body: JSON.stringify({ name }),
      });
      setActiveProfile(name);
      load();
    } catch (e) {
      setError(readableError(e, "Failed to switch profile"));
    } finally {
      setSettingActive(null);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    setError(null);
    try {
      await apiFetch(`/api/profiles/${encodeURIComponent(deleteTarget)}`, {
        method: "DELETE",
      });
      setDeleteTarget(null);
      load();
    } catch (e) {
      setError(readableError(e, "Failed to delete profile"));
    } finally {
      setDeleting(false);
    }
  };

  const handleRename = async () => {
    if (!renamingFrom) return;
    const target = renameTo.trim();
    if (!target || !PROFILE_NAME_RE.test(target)) {
      setRenamingFrom(null);
      return;
    }
    setRenameSaving(true);
    setError(null);
    try {
      await apiFetch(
        `/api/profiles/${encodeURIComponent(renamingFrom)}/rename`,
        {
          method: "PUT",
          body: JSON.stringify({ name: target }),
        },
      );
      setRenamingFrom(null);
      load();
    } catch (e) {
      setError(readableError(e, "Failed to rename profile"));
    } finally {
      setRenameSaving(false);
    }
  };

  const handleSetModel = async () => {
    if (!editModelFor || !modelChoice) return;
    setModelSaving(true);
    setError(null);
    try {
      const choice = modelChoices.find(
        (c) => `${c.provider}\0${c.model}` === modelChoice,
      );
      if (choice) {
        await apiFetch(
          `/api/profiles/${encodeURIComponent(editModelFor)}/model`,
          {
            method: "PUT",
            body: JSON.stringify({
              provider: choice.provider,
              model: choice.model,
            }),
          },
        );
      }
      setEditModelFor(null);
      load();
    } catch (e) {
      setError(readableError(e, "Failed to update model"));
    } finally {
      setModelSaving(false);
    }
  };

  const handleClone = async () => {
    const name = cloneName.trim();
    if (!name || !PROFILE_NAME_RE.test(name)) {
      setError("Invalid profile name for clone.");
      return;
    }
    setCloning(true);
    setError(null);
    try {
      await apiFetch("/api/profiles", {
        method: "POST",
        body: JSON.stringify({
          name,
          description: cloneDescription.trim() || undefined,
          clone_from: cloneSource || undefined,
        }),
      });
      setCloneOpen(false);
      setCloneName("");
      setCloneDescription("");
      setCloneSource("");
      load();
    } catch (e) {
      setError(readableError(e, "Failed to clone profile"));
    } finally {
      setCloning(false);
    }
  };

  const openCloneFor = (sourceName: string) => {
    setCloneSource(sourceName);
    setCloneName(`${sourceName}-copy`);
    setCloneDescription("");
    setCloneOpen(true);
  };

  // ── Render ──────────────────────────────────────────────────────────

  if (loading)
    return (
      <div className="page-stack">
        <PageHeader
          title="Profiles"
          description="Manage agent profiles."
        />
        <div className="flex items-center justify-center py-12 text-muted-foreground">
          Loading…
        </div>
      </div>
    );

  return (
    <div className="page-stack">
      <PageHeader
        title="Profiles"
        description="Manage agent profiles for different configurations. Each profile can have its own model, skills, and settings."
        action={
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={load}>
              <RefreshCw className="h-4 w-4 mr-1" />
              Refresh
            </Button>
            <Button size="sm" onClick={() => setCreateOpen(true)}>
              <Plus className="h-4 w-4 mr-1" />
              New Profile
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      <div className="grid gap-3">
        {profiles.map((profile) => {
          const isActive =
            profile.name === activeProfile ||
            (activeProfile === "default" && profile.is_default);

          return (
            <Card
              key={profile.name}
              className={isActive ? "ring-1 ring-primary/40" : ""}
            >
              <CardContent className="flex items-center justify-between gap-4 p-4">
                <div className="flex-1 min-w-0">
                  {/* ── Name row ── */}
                  <div className="flex items-center gap-2 mb-1">
                    <div
                      className={`flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold ${
                        isActive
                          ? "bg-primary text-primary-foreground"
                          : "bg-muted text-muted-foreground"
                      }`}
                    >
                      <User className="h-3.5 w-3.5" />
                    </div>
                    {renamingFrom === profile.name ? (
                      <div className="flex items-center gap-2">
                        <Input
                          className="h-7 text-sm font-mono w-40"
                          value={renameTo}
                          onChange={(e) => setRenameTo(e.target.value)}
                          autoFocus
                          onKeyDown={(e) => {
                            if (e.key === "Enter") handleRename();
                            if (e.key === "Escape") setRenamingFrom(null);
                          }}
                        />
                        <Button
                          size="sm"
                          onClick={handleRename}
                          disabled={renameSaving}
                        >
                          {renameSaving ? "…" : "Save"}
                        </Button>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => setRenamingFrom(null)}
                        >
                          Cancel
                        </Button>
                      </div>
                    ) : (
                      <span className="font-mono text-sm font-semibold">
                        {profile.name}
                      </span>
                    )}
                    {isActive && (
                      <Badge className="bg-primary/15 text-xs">
                        <Check className="h-2.5 w-2.5 mr-0.5" />
                        active
                      </Badge>
                    )}
                    {profile.is_default && !isActive && (
                      <Badge variant="outline" className="text-xs">
                        default
                      </Badge>
                    )}
                  </div>

                  {/* ── Description ── */}
                  {profile.description && (
                    <p className="text-xs text-muted-foreground truncate ml-9">
                      {profile.description}
                    </p>
                  )}

                  {/* ── Model & Skills badges ── */}
                  <div className="flex items-center gap-2 mt-1 ml-9 flex-wrap">
                    {(profile.provider || profile.model) && (
                      <Badge variant="secondary" className="text-xs font-mono">
                        <Cpu className="h-2.5 w-2.5 mr-1" />
                        {profile.provider
                          ? `${profile.provider}/${profile.model ?? "default"}`
                          : profile.model}
                      </Badge>
                    )}
                    {profile.skills_count !== undefined &&
                      profile.skills_count > 0 && (
                        <Badge variant="outline" className="text-xs">
                          {profile.skills_count} skill
                          {profile.skills_count !== 1 ? "s" : ""}
                        </Badge>
                      )}
                  </div>

                  {/* ── Inline model editor ── */}
                  {editModelFor === profile.name && (
                    <div className="flex items-center gap-2 mt-2 ml-9">
                      <Select value={modelChoice} onValueChange={setModelChoice}>
                        <SelectTrigger className="h-7 text-sm w-64">
                          <SelectValue placeholder="Select model" />
                        </SelectTrigger>
                        <SelectContent>
                          {modelChoices.map((c) => (
                            <SelectItem
                              key={`${c.provider}\0${c.model}`}
                              value={`${c.provider}\0${c.model}`}
                            >
                              {c.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Button
                        size="sm"
                        onClick={handleSetModel}
                        disabled={modelSaving || !modelChoice}
                      >
                        {modelSaving ? "…" : "Set"}
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setEditModelFor(null)}
                      >
                        Cancel
                      </Button>
                    </div>
                  )}
                </div>

                {/* ── Action buttons ── */}
                <div className="flex items-center gap-1 shrink-0">
                  {!isActive && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleSetActive(profile.name)}
                      disabled={settingActive === profile.name}
                    >
                      {settingActive === profile.name
                        ? "Switching…"
                        : "Set Active"}
                    </Button>
                  )}
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                      >
                        <MoreVertical className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        onClick={() => {
                          setEditModelFor(profile.name);
                          setModelChoice(
                            profile.provider && profile.model
                              ? `${profile.provider}\0${profile.model}`
                              : "",
                          );
                        }}
                      >
                        <Cpu className="h-4 w-4 mr-2" />
                        Change model
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        onClick={() => {
                          setRenamingFrom(profile.name);
                          setRenameTo(profile.name);
                        }}
                      >
                        <Pencil className="h-4 w-4 mr-2" />
                        Rename
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        onClick={() => openCloneFor(profile.name)}
                      >
                        <Copy className="h-4 w-4 mr-2" />
                        Clone
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem
                        variant="destructive"
                        disabled={profile.is_default}
                        onClick={() => {
                          if (!profile.is_default)
                            setDeleteTarget(profile.name);
                        }}
                      >
                        <Trash2 className="h-4 w-4 mr-2" />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </CardContent>
            </Card>
          );
        })}

        {profiles.length === 0 && !loading && (
          <div className="text-center py-12 text-muted-foreground">
            <User className="h-10 w-10 mx-auto mb-3 opacity-50" />
            <p className="text-sm">No profiles found.</p>
            <p className="text-xs mt-1">
              Create a profile to configure different agent personas.
            </p>
          </div>
        )}
      </div>

      {/* ── Create Dialog ── */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Create Profile</DialogTitle>
            <DialogDescription>
              Create a new agent profile with its own settings.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="profile-name">Name</Label>
              <Input
                id="profile-name"
                autoFocus
                placeholder="my-profile"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleCreate();
                }}
              />
              <p className="text-xs text-muted-foreground">
                Lowercase letters, numbers, hyphens, underscores. 1–64 chars.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="profile-desc">Description (optional)</Label>
              <Input
                id="profile-desc"
                placeholder="What is this profile for?"
                value={newDescription}
                onChange={(e) => setNewDescription(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label>Clone from (optional)</Label>
              <Select
                value={newCloneFrom}
                onValueChange={(v) => setNewCloneFrom(v === "__none__" ? "" : v)}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Start from scratch" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">Start from scratch</SelectItem>
                  {profiles.map((p) => (
                    <SelectItem key={p.name} value={p.name}>
                      {p.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setCreateOpen(false)}
              disabled={creating}
            >
              Cancel
            </Button>
            <Button onClick={handleCreate} disabled={creating}>
              {creating ? "Creating…" : "Create"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Clone Dialog ── */}
      <Dialog open={cloneOpen} onOpenChange={setCloneOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Clone Profile</DialogTitle>
            <DialogDescription>
              Create a copy of <span className="font-mono">{cloneSource}</span>{" "}
              with a new name.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="clone-name">New profile name</Label>
              <Input
                id="clone-name"
                autoFocus
                value={cloneName}
                onChange={(e) => setCloneName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleClone();
                }}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="clone-desc">Description (optional)</Label>
              <Input
                id="clone-desc"
                placeholder="Description for the cloned profile"
                value={cloneDescription}
                onChange={(e) => setCloneDescription(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setCloneOpen(false)}
              disabled={cloning}
            >
              Cancel
            </Button>
            <Button onClick={handleClone} disabled={cloning}>
              {cloning ? "Cloning…" : "Clone"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Delete AlertDialog ── */}
      <AlertDialog
        open={!!deleteTarget}
        onOpenChange={(open) => {
          if (!open) setDeleteTarget(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Profile</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete the profile{" "}
              <span className="font-mono font-semibold">{deleteTarget}</span>{" "}
              and all its data. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleting ? "Deleting…" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
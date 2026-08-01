export type StudioKind = "image" | "video" | "audio" | "writing" | "presentation" | "3d";

export interface StudioProject {
  id: string;
  title: string;
  kind: StudioKind;
  prompt: string;
  status: "concept" | "in_progress" | "review" | "complete";
  createdAt: string;
  updatedAt: string;
}

export interface StudioAsset {
  id: string;
  name: string;
  kind: StudioKind;
  location: string;
  projectId?: string;
  createdAt: string;
}

export interface StudioState {
  projects: StudioProject[];
  assets: StudioAsset[];
}

export const EMPTY_STUDIO_STATE: StudioState = { projects: [], assets: [] };

export const STUDIO_KIND_LABELS: Record<StudioKind, string> = {
  image: "Image",
  video: "Video",
  audio: "Audio",
  writing: "Writing",
  presentation: "Presentation",
  "3d": "3D",
};

export function studioId(prefix: string): string {
  return `${prefix}-${globalThis.crypto?.randomUUID?.() ?? Date.now().toString(36)}`;
}

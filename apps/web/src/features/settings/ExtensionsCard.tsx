import { LoaderCircle } from "lucide-react";
import type { Dispatch, SetStateAction } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";

import { asBool } from "./helpers";

export function ExtensionsCard({
  plugins,
  extensions,
  setExtensions,
  extStatus,
  listsLoading,
  flash,
  setError,
}: {
  plugins: Array<Record<string, unknown>>;
  extensions: Array<Record<string, unknown>>;
  setExtensions: Dispatch<SetStateAction<Array<Record<string, unknown>>>>;
  extStatus: Record<string, unknown> | null;
  listsLoading: boolean;
  flash: (message: string) => void;
  setError: (message: string) => void;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Extensions</CardTitle>
        <CardDescription>Installed ARES plugins and browser extensions.</CardDescription>
      </CardHeader>
      <CardContent className="grid gap-5">
        <section className="grid gap-2">
          <h4 className="text-sm font-semibold">Plugins</h4>
          {listsLoading ? <Loading /> : plugins.length === 0 ? (
            <p className="text-sm text-muted-foreground">No plugins reported by ARES.</p>
          ) : plugins.map((plugin, index) => {
            const name = String(plugin.name || plugin.id || `plugin-${index}`);
            return (
              <div key={name} className="rounded-lg border px-3 py-2">
                <p className="text-sm font-medium">{name}</p>
                {plugin.description || plugin.summary ? <p className="text-xs text-muted-foreground">{String(plugin.description || plugin.summary)}</p> : null}
              </div>
            );
          })}
        </section>
        <section className="grid gap-2">
          <h4 className="text-sm font-semibold">Web extensions</h4>
          {extStatus ? <p className="text-xs font-mono text-muted-foreground">Status: {JSON.stringify(extStatus).slice(0, 180)}</p> : null}
          {listsLoading ? <Loading /> : extensions.length === 0 ? (
            <p className="text-sm text-muted-foreground">No extensions in the registry.</p>
          ) : extensions.map((extension, index) => {
            const id = String(extension.id || extension.name || `ext-${index}`);
            const enabled = asBool(extension.enabled ?? extension.user_enabled, true);
            return (
              <div key={id} className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{String(extension.name || id)}</p>
                  <p className="truncate text-xs text-muted-foreground">{String(extension.description || id)}</p>
                </div>
                <ToggleSwitch
                  checked={enabled}
                  onCheckedChange={(value) => {
                    void aresApi.toggleExtension(id, value).then(() => {
                      setExtensions((current) => current.map((item) => String(item.id || item.name) === id ? { ...item, enabled: value, user_enabled: value } : item));
                      flash(value ? "Extension enabled" : "Extension disabled");
                    }).catch((reason) => setError(readableError(reason, "Could not toggle extension.")));
                  }}
                />
              </div>
            );
          })}
        </section>
      </CardContent>
    </Card>
  );
}

function Loading() {
  return <div className="flex items-center gap-2 text-sm text-muted-foreground"><LoaderCircle className="size-4 animate-spin" /> Loading…</div>;
}

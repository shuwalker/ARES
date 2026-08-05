import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import type { LucideIcon } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { cn } from "@/lib/utils";

export type SurfaceLink = {
  to: string;
  label: string;
  description: string;
  icon: LucideIcon;
};

/**
 * Shared chrome for the product surfaces (Companion, Self, Engineering,
 * Library, Control Center hubs). Keeps domain pages visually consistent without
 * forcing every child route into a single layout tree.
 */
export function SurfaceShell({
  title,
  description,
  action,
  children,
  className,
}: {
  title: string;
  description: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("mx-auto flex w-full max-w-5xl flex-col gap-6 p-6", className)}>
      <PageHeader title={title} description={description} action={action} />
      {children}
    </div>
  );
}

export function SurfaceLinkGrid({ links }: { links: SurfaceLink[] }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {links.map(({ to, label, description, icon: Icon }) => (
        <Link
          key={to}
          to={to}
          className="group rounded-lg border border-border bg-card p-4 transition-colors hover:border-primary/50 hover:bg-accent/40"
        >
          <div className="flex items-start gap-3">
            <span className="grid size-9 shrink-0 place-items-center rounded-md border border-border bg-background text-primary">
              <Icon className="size-4" />
            </span>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-foreground group-hover:text-primary">{label}</p>
              <p className="mt-1 text-xs leading-relaxed text-foreground/80">{description}</p>
            </div>
          </div>
        </Link>
      ))}
    </div>
  );
}

export function SurfaceNote({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-md border border-dashed border-border/80 bg-card/40 px-3.5 py-2.5 text-xs leading-relaxed text-foreground/80">
      {children}
    </p>
  );
}

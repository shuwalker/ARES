export type DomainSelectionSource = "manual" | "route_sync" | "bootstrap";

export function shouldSyncDomainSelectionFromRoute(params: {
  selectionSource: DomainSelectionSource;
  selectedDomainId: string | null;
  routeDomainId: string;
}): boolean {
  const { selectionSource, selectedDomainId, routeDomainId } = params;

  if (selectedDomainId === routeDomainId) return false;

  // Let manual domain switches finish their remembered-path navigation first.
  if (selectionSource === "manual" && selectedDomainId) {
    return false;
  }

  return true;
}

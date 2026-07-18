import {
  AlertTriangle,
  BarChart3,
  CircleDollarSign,
  Clock,
  Coins,
  Flame,
  Percent,
  ShieldCheck,
  ShieldAlert,
  type LucideIcon,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { useTheme } from "@/context/ThemeContext";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import {
  EMPTY_USAGE_INSIGHTS,
  type ProviderQuotaInfo,
  type UsageBreakdownRow,
  type UsageInsights,
} from "@/shared/contracts";

// ── Palette ────────────────────────────────────────────────────────────────
// Validated categorical pair for the two-series token chart (dataviz skill,
// palette.md slots 1-2: blue/aqua — CVD-safe adjacent ordering, checked with
// scripts/validate_palette.js against both surfaces). Cost reuses slot 1 as a
// single sequential hue since it's a lone series (no legend needed).
const CHART_COLORS = {
  light: { input: "#2a78d6", output: "#1baf7a", cost: "#2a78d6", grid: "#e1e0d9", axis: "#898781" },
  dark: { input: "#3987e5", output: "#199e70", cost: "#3987e5", grid: "#2c2c2a", axis: "#898781" },
};

const HEATMAP_LOW = "#1a3a2a";
const HEATMAP_MID = "#1baf7a";
const HEATMAP_HIGH = "#3987e5";

const RANGE_OPTIONS = [
  { value: "7", label: "Last 7 days" },
  { value: "30", label: "Last 30 days" },
  { value: "90", label: "Last 90 days" },
];

// ── Formatters ──────────────────────────────────────────────────────────────
function formatCompactNumber(value: number): string {
  return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(value);
}

function formatCurrency(value: number): string {
  if (value > 0 && value < 0.01) return "<$0.01";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: value < 1 ? 4 : 2,
  }).format(value);
}

function formatDuration(seconds: number): string {
  if (!seconds) return "0m";
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.round((seconds % 3600) / 60);
  if (hours && minutes) return `${hours}h ${minutes}m`;
  if (hours) return `${hours}h`;
  return `${minutes}m`;
}

function formatDayLabel(date: string): string {
  const parsed = new Date(`${date}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return date;
  return parsed.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function formatPercent(value: number): string {
  return `${value.toFixed(1)}%`;
}

// ── KPI Tile ────────────────────────────────────────────────────────────────
function KpiTile({
  icon: Icon,
  label,
  value,
  detail,
  loading,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  detail?: string;
  loading: boolean;
}) {
  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2">
        <Icon className="size-4 text-muted-foreground" aria-hidden="true" />
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? <Skeleton className="h-8 w-24" /> : <p className="text-2xl font-semibold tracking-tight">{value}</p>}
        {detail ? <p className="mt-1 text-xs text-muted-foreground">{detail}</p> : null}
      </CardContent>
    </Card>
  );
}

// ── Tooltip components ───────────────────────────────────────────────────────
interface TooltipEntry {
  dataKey: string;
  value: number;
  color: string;
}

function TokensTooltip({ active, payload, label }: { active?: boolean; payload?: TooltipEntry[]; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <p className="mb-1 font-medium text-popover-foreground">{formatDayLabel(label || "")}</p>
      {payload.map((entry) => (
        <p key={entry.dataKey} className="flex items-center gap-2 text-popover-foreground">
          <span aria-hidden="true" className="inline-block h-0.5 w-3" style={{ backgroundColor: entry.color }} />
          <span className="font-medium tabular-nums">{formatCompactNumber(entry.value)}</span>
          <span className="text-muted-foreground">{entry.dataKey === "inputTokens" ? "input" : "output"}</span>
        </p>
      ))}
    </div>
  );
}

function CostTooltip({ active, payload, label }: { active?: boolean; payload?: TooltipEntry[]; label?: string }) {
  if (!active || !payload?.length) return null;
  const entry = payload[0];
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <p className="mb-1 font-medium text-popover-foreground">{formatDayLabel(label || "")}</p>
      <p className="flex items-center gap-2 text-popover-foreground">
        <span aria-hidden="true" className="inline-block h-0.5 w-3" style={{ backgroundColor: entry.color }} />
        <span className="font-medium tabular-nums">{formatCurrency(entry.value)}</span>
      </p>
    </div>
  );
}

function SessionsTooltip({ active, payload, label }: { active?: boolean; payload?: TooltipEntry[]; label?: string }) {
  if (!active || !payload?.length) return null;
  const entry = payload[0];
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <p className="mb-1 font-medium text-popover-foreground">{label}</p>
      <p className="flex items-center gap-2 text-popover-foreground">
        <span className="font-medium tabular-nums">{entry.value}</span>
        <span className="text-muted-foreground">sessions</span>
      </p>
    </div>
  );
}

// ── Share bar ───────────────────────────────────────────────────────────────
function ShareBar({ percent, color }: { percent: number; color?: string }) {
  const clamped = Math.min(Math.max(percent, 0), 100);
  const barColor = color ?? (clamped > 80 ? "var(--destructive)" : clamped > 50 ? "var(--warning)" : "var(--chart-2, #1baf7a)");
  return (
    <div className="h-1.5 w-full rounded-full bg-muted" role="progressbar" aria-valuenow={clamped} aria-valuemin={0} aria-valuemax={100}>
      <div
        className="h-full rounded-full transition-all duration-300"
        style={{ width: `${clamped}%`, backgroundColor: barColor }}
      />
    </div>
  );
}

// ── Budget status card ───────────────────────────────────────────────────────
function BudgetCard({ quota, loading }: { quota: ProviderQuotaInfo | null; loading: boolean }) {
  if (loading) return <Card><CardContent className="pt-6"><Skeleton className="h-20 w-full" /></CardContent></Card>;
  if (!quota || !quota.ok || !quota.supported || !quota.quota) {
    return (
      <Card>
        <CardHeader className="flex-row items-center gap-2">
          <ShieldAlert className="size-4 text-muted-foreground" aria-hidden="true" />
          <CardTitle className="text-sm font-medium text-muted-foreground">Provider budget</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            {quota ? quota.message : "No budget data available."}
          </p>
        </CardContent>
      </Card>
    );
  }

  const total = quota.quota.total ?? 0;
  const remaining = quota.quota.remaining ?? 0;
  const usage = quota.quota.usage ?? (total - remaining);
  const pct = total > 0 ? Math.round((usage / total) * 100) : 0;
  const isDollar = quota.label?.toLowerCase().includes("credit") || quota.label?.toLowerCase().includes("$");
  const usageLabel = isDollar ? formatCurrency(usage) : formatCompactNumber(usage);
  const totalLabel = isDollar ? formatCurrency(total) : formatCompactNumber(total);

  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2">
        <ShieldCheck className="size-4 text-muted-foreground" aria-hidden="true" />
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {quota.displayName ?? quota.provider ?? "Provider"} budget
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-baseline justify-between">
          <p className="text-2xl font-semibold tracking-tight">
            {usageLabel} <span className="text-sm font-normal text-muted-foreground">/ {totalLabel}</span>
          </p>
          <Badge variant={pct > 80 ? "destructive" : pct > 50 ? "secondary" : "outline"}>
            {formatPercent(pct)} used
          </Badge>
        </div>
        <ShareBar percent={pct} />
        {quota.quota.rateLimits && Object.keys(quota.quota.rateLimits).length > 0 && (
          <div className="space-y-1 text-xs text-muted-foreground">
            {Object.entries(quota.quota.rateLimits).map(([window, info]) => (
              <div key={window} className="flex justify-between">
                <span>{window}</span>
                <span className="tabular-nums">{info.remaining}/{info.limit}</span>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ── Breakdown table with share bars ──────────────────────────────────────────
function BreakdownTable({
  title,
  columnLabel,
  rows,
  showShareBar,
}: {
  title: string;
  columnLabel: string;
  rows: UsageBreakdownRow[];
  showShareBar?: "cost" | "tokens";
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {rows.length ? (
          <div className="text-sm">
            <div className="flex items-center gap-3 border-b pb-2 text-xs font-medium text-muted-foreground">
              <span className="min-w-0 flex-1 truncate">{columnLabel}</span>
              <span className="w-16 text-right">Sessions</span>
              <span className="w-20 text-right">Tokens</span>
              <span className="w-20 text-right">Cost</span>
              {showShareBar && <span className="w-24" />}
            </div>
            <div className="divide-y">
              {rows.map((row) => (
                <div key={row.key} className="flex items-center gap-3 py-2">
                  <span className="min-w-0 flex-1 truncate" title={row.key}>{row.key}</span>
                  <span className="w-16 text-right tabular-nums text-muted-foreground">{row.sessions}</span>
                  <span className="w-20 text-right tabular-nums text-muted-foreground">{formatCompactNumber(row.totalTokens)}</span>
                  <span className="w-20 text-right tabular-nums font-medium">{formatCurrency(row.cost)}</span>
                  {showShareBar && (
                    <div className="w-24">
                      <ShareBar percent={showShareBar === "cost" ? row.costShare : row.tokenShare} />
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">No usage recorded for this range.</p>
        )}
      </CardContent>
    </Card>
  );
}

// ── Activity heatmap (by day-of-week & hour) ───────────────────────────────
function ActivityHeatmap({
  byDay,
  byHour,
}: {
  byDay: UsageInsights["activityByDay"];
  byHour: UsageInsights["activityByHour"];
}) {
  const dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const dayMap = useMemo(() => {
    const map = new Map<string, number>();
    for (const d of byDay) map.set(d.day, d.sessions);
    return map;
  }, [byDay]);
  const hourMap = useMemo(() => {
    const map = new Map<number, number>();
    for (const h of byHour) map.set(h.hour, h.sessions);
    return map;
  }, [byHour]);

  const maxHour = useMemo(() => {
    let m = 0;
    for (const h of byHour) if (h.sessions > m) m = h.sessions;
    return m || 1;
  }, [byHour]);

  const maxDay = useMemo(() => {
    let m = 0;
    for (const d of byDay) if (d.sessions > m) m = d.sessions;
    return m || 1;
  }, [byDay]);

  function heatColor(value: number, max: number): string {
    if (value === 0) return "var(--muted)";
    const ratio = value / max;
    if (ratio < 0.33) return HEATMAP_LOW;
    if (ratio < 0.66) return HEATMAP_MID;
    return HEATMAP_HIGH;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">Activity patterns</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* By day of week */}
        <div>
          <p className="mb-2 text-xs text-muted-foreground">By day of week</p>
          <div className="flex items-end gap-1">
            {dayLabels.map((label, idx) => {
              const count = dayMap.get(label) ?? 0;
              return (
                <div key={label} className="flex flex-1 flex-col items-center gap-1">
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {count > 0 ? formatCompactNumber(count) : "—"}
                  </span>
                  <div
                    className="w-full rounded-sm transition-colors"
                    style={{
                      height: `${Math.max(4, (count / maxDay) * 40)}px`,
                      backgroundColor: heatColor(count, maxDay),
                    }}
                  />
                  <span className="text-[10px] text-muted-foreground">{label}</span>
                </div>
              );
            })}
          </div>
        </div>
        {/* By hour */}
        <div>
          <p className="mb-2 text-xs text-muted-foreground">By hour (local)</p>
          <div className="flex items-end gap-px">
            {Array.from({ length: 24 }, (_, h) => {
              const count = hourMap.get(h) ?? 0;
              return (
                <div
                  key={h}
                  className="flex-1 rounded-sm transition-colors"
                  style={{
                    height: `${Math.max(2, (count / maxHour) * 32)}px`,
                    backgroundColor: heatColor(count, maxHour),
                  }}
                  title={`${h}:00 — ${count} sessions`}
                />
              );
            })}
          </div>
          <div className="mt-1 flex justify-between text-[10px] text-muted-foreground">
            <span>0h</span>
            <span>6h</span>
            <span>12h</span>
            <span>18h</span>
            <span>23h</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ── Main page ────────────────────────────────────────────────────────────────
export function UsageCostPage() {
  const { theme } = useTheme();
  const colors = theme === "dark" ? CHART_COLORS.dark : CHART_COLORS.light;
  const [days, setDays] = useState(30);
  const [data, setData] = useState<UsageInsights>(EMPTY_USAGE_INSIGHTS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [quota, setQuota] = useState<ProviderQuotaInfo | null>(null);
  const [quotaLoading, setQuotaLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    setError("");
    aresApi
      .insights(days)
      .then(setData)
      .catch((reason) => setError(readableError(reason, "Usage data could not be loaded.")))
      .finally(() => setLoading(false));
  }, [days]);

  useEffect(() => {
    setQuotaLoading(true);
    aresApi
      .providerQuota()
      .then((raw) => {
        const q = raw.quota as Record<string, unknown> | undefined | null;
        const rl = q && typeof q.rate_limits === "object" && q.rate_limits ? (q.rate_limits as Record<string, Record<string, unknown>>) : undefined;
        setQuota({
          ok: Boolean(raw.ok),
          provider: typeof raw.provider === "string" ? raw.provider : null,
          displayName: typeof raw.display_name === "string" ? raw.display_name : null,
          supported: Boolean(raw.supported),
          status: String(raw.status ?? ""),
          label: typeof raw.label === "string" ? raw.label : undefined,
          quota: q
            ? {
                remaining: typeof q.remaining === "number" ? q.remaining : undefined,
                total: typeof q.total === "number" ? q.total : undefined,
                usage: typeof q.usage === "number" ? q.usage : undefined,
                rateLimits: rl
                  ? Object.fromEntries(
                      Object.entries(rl).map(([k, v]) => [
                        k,
                        {
                          limit: Number(v.limit ?? 0),
                          remaining: Number(v.remaining ?? 0),
                          reset: Number(v.reset ?? 0),
                        },
                      ]),
                    )
                  : undefined,
              }
            : null,
          message: String(raw.message ?? ""),
        });
      })
      .catch(() => setQuota(null))
      .finally(() => setQuotaLoading(false));
  }, []);

  const dailyChartData = useMemo(
    () => data.dailyTokens.map((point) => ({ ...point, dayLabel: formatDayLabel(point.date) })),
    [data.dailyTokens],
  );

  // Average daily cost for trend context
  const avgDailyCost = useMemo(() => {
    if (!dailyChartData.length) return 0;
    return dailyChartData.reduce((sum, d) => sum + d.cost, 0) / dailyChartData.length;
  }, [dailyChartData]);

  // Provider share for top-level context
  const topProvider = useMemo(() => {
    if (!data.providers.length) return null;
    return data.providers[0]; // already sorted by cost desc
  }, [data.providers]);

  return (
    <div className="page-stack">
      <PageHeader
        title="Usage & Cost"
        description="Track tokens, cost, and session activity across models and providers."
        action={
          <Select value={String(days)} onValueChange={(value) => setDays(Number(value))}>
            <SelectTrigger className="w-40" aria-label="Date range"><SelectValue /></SelectTrigger>
            <SelectContent>
              {RANGE_OPTIONS.map((option) => (
                <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        }
      />
      {error ? <p className="text-sm text-status-limited">{error}</p> : null}

      {/* ── KPI row ─────────────────────────────────────────────────────── */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <KpiTile icon={CircleDollarSign} label="Total cost" value={formatCurrency(data.totalCost)} detail={avgDailyCost > 0 ? `~${formatCurrency(avgDailyCost)}/day avg` : undefined} loading={loading} />
        <KpiTile
          icon={Coins}
          label="Total tokens"
          value={formatCompactNumber(data.totalTokens)}
          detail={`${formatCompactNumber(data.totalInputTokens)} in / ${formatCompactNumber(data.totalOutputTokens)} out`}
          loading={loading}
        />
        <KpiTile icon={BarChart3} label="Sessions" value={formatCompactNumber(data.totalSessions)} loading={loading} />
        <KpiTile
          icon={Percent}
          label="Cache hit rate"
          value={data.totalCacheHitPercent === null ? "—" : `${data.totalCacheHitPercent}%`}
          loading={loading}
        />
        <KpiTile icon={Clock} label="Avg session span" value={formatDuration(data.averageSessionDurationSeconds)} loading={loading} />
      </div>

      {/* ── Budget status + top provider ──────────────────────────────── */}
      <div className="grid gap-4 lg:grid-cols-2">
        <BudgetCard quota={quota} loading={quotaLoading} />
        {topProvider ? (
          <Card>
            <CardHeader className="flex-row items-center gap-2">
              <Flame className="size-4 text-muted-foreground" aria-hidden="true" />
              <CardTitle className="text-sm font-medium text-muted-foreground">Top provider</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <p className="text-lg font-semibold">{topProvider.key}</p>
              <div className="flex gap-4 text-sm text-muted-foreground">
                <span>{formatCompactNumber(topProvider.sessions)} sessions</span>
                <span>{formatCompactNumber(topProvider.totalTokens)} tokens</span>
                <span className="font-medium text-foreground">{formatCurrency(topProvider.cost)}</span>
              </div>
              <ShareBar percent={topProvider.costShare} />
              <p className="text-xs text-muted-foreground">{formatPercent(topProvider.costShare)} of total cost</p>
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardHeader className="flex-row items-center gap-2">
              <Flame className="size-4 text-muted-foreground" aria-hidden="true" />
              <CardTitle className="text-sm font-medium text-muted-foreground">Top provider</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-muted-foreground">No provider data for this range.</p>
            </CardContent>
          </Card>
        )}
      </div>

      {/* ── Charts ────────────────────────────────────────────────────── */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">Tokens by day</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="mb-2 flex items-center gap-4 text-xs text-muted-foreground">
              <span className="flex items-center gap-1.5">
                <span aria-hidden="true" className="inline-block size-2 rounded-full" style={{ backgroundColor: colors.input }} />
                Input
              </span>
              <span className="flex items-center gap-1.5">
                <span aria-hidden="true" className="inline-block size-2 rounded-full" style={{ backgroundColor: colors.output }} />
                Output
              </span>
            </div>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={dailyChartData}>
                <CartesianGrid vertical={false} stroke={colors.grid} />
                <XAxis dataKey="dayLabel" tick={{ fontSize: 11, fill: colors.axis }} axisLine={{ stroke: colors.grid }} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 11, fill: colors.axis }} axisLine={false} tickLine={false} tickFormatter={formatCompactNumber} width={40} />
                <Tooltip content={<TokensTooltip />} cursor={{ fill: "var(--muted)" }} />
                <Bar dataKey="inputTokens" stackId="tokens" fill={colors.input} maxBarSize={24} />
                <Bar dataKey="outputTokens" stackId="tokens" fill={colors.output} radius={[4, 4, 0, 0]} maxBarSize={24} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">Cost by day</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={dailyChartData}>
                <CartesianGrid vertical={false} stroke={colors.grid} />
                <XAxis dataKey="dayLabel" tick={{ fontSize: 11, fill: colors.axis }} axisLine={{ stroke: colors.grid }} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 11, fill: colors.axis }} axisLine={false} tickLine={false} tickFormatter={(value: number) => formatCurrency(value)} width={56} />
                <Tooltip content={<CostTooltip />} cursor={{ stroke: colors.grid }} />
                <Line type="monotone" dataKey="cost" stroke={colors.cost} strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      {/* ── Sessions by day chart ──────────────────────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">Sessions by day</CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={dailyChartData}>
              <CartesianGrid vertical={false} stroke={colors.grid} />
              <XAxis dataKey="dayLabel" tick={{ fontSize: 11, fill: colors.axis }} axisLine={{ stroke: colors.grid }} tickLine={false} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 11, fill: colors.axis }} axisLine={false} tickLine={false} width={32} />
              <Tooltip content={<SessionsTooltip />} cursor={{ fill: "var(--muted)" }} />
              <Bar dataKey="sessions" maxBarSize={16} radius={[3, 3, 0, 0]}>
                {dailyChartData.map((entry, idx) => (
                  <Cell key={idx} fill={entry.sessions > 0 ? colors.cost : "var(--muted)"} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      {/* ── Breakdown tables with share bars ──────────────────────────── */}
      <div className="grid gap-4 lg:grid-cols-2">
        <BreakdownTable title="By model" columnLabel="Model" rows={data.models} showShareBar="cost" />
        <BreakdownTable title="By provider" columnLabel="Provider" rows={data.providers} showShareBar="cost" />
      </div>

      {/* ── Activity heatmap ──────────────────────────────────────────── */}
      <ActivityHeatmap byDay={data.activityByDay} byHour={data.activityByHour} />
    </div>
  );
}
import { BarChart3, CircleDollarSign, Clock, Coins, Percent, type LucideIcon } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { useTheme } from "@/context/ThemeContext";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { EMPTY_USAGE_INSIGHTS, type UsageBreakdownRow, type UsageInsights } from "@/shared/contracts";

// Validated categorical pair for the two-series token chart (dataviz skill,
// palette.md slots 1-2: blue/aqua — CVD-safe adjacent ordering, checked with
// scripts/validate_palette.js against both surfaces). Cost reuses slot 1 as a
// single sequential hue since it's a lone series (no legend needed).
const CHART_COLORS = {
  light: { input: "#2a78d6", output: "#1baf7a", cost: "#2a78d6", grid: "#e1e0d9", axis: "#898781" },
  dark: { input: "#3987e5", output: "#199e70", cost: "#3987e5", grid: "#2c2c2a", axis: "#898781" },
};

const RANGE_OPTIONS = [
  { value: "7", label: "Last 7 days" },
  { value: "30", label: "Last 30 days" },
  { value: "90", label: "Last 90 days" },
];

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

function BreakdownTable({ title, columnLabel, rows }: { title: string; columnLabel: string; rows: UsageBreakdownRow[] }) {
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
            </div>
            <div className="divide-y">
              {rows.map((row) => (
                <div key={row.key} className="flex items-center gap-3 py-2">
                  <span className="min-w-0 flex-1 truncate" title={row.key}>{row.key}</span>
                  <span className="w-16 text-right tabular-nums text-muted-foreground">{row.sessions}</span>
                  <span className="w-20 text-right tabular-nums text-muted-foreground">{formatCompactNumber(row.totalTokens)}</span>
                  <span className="w-20 text-right tabular-nums font-medium">{formatCurrency(row.cost)}</span>
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

export function UsageCostPage() {
  const { theme } = useTheme();
  const colors = theme === "dark" ? CHART_COLORS.dark : CHART_COLORS.light;
  const [days, setDays] = useState(30);
  const [data, setData] = useState<UsageInsights>(EMPTY_USAGE_INSIGHTS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    setLoading(true);
    setError("");
    aresApi
      .insights(days)
      .then(setData)
      .catch((reason) => setError(readableError(reason, "Usage data could not be loaded.")))
      .finally(() => setLoading(false));
  }, [days]);

  const dailyChartData = useMemo(
    () => data.dailyTokens.map((point) => ({ ...point, dayLabel: formatDayLabel(point.date) })),
    [data.dailyTokens],
  );

  return (
    <div className="page-stack">
      <PageHeader
        title="Usage & Cost"
        description="Track tokens, cost, and session span across models and providers."
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
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <KpiTile icon={CircleDollarSign} label="Total cost" value={formatCurrency(data.totalCost)} loading={loading} />
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
      <div className="grid gap-4 lg:grid-cols-2">
        <BreakdownTable title="By model" columnLabel="Model" rows={data.models} />
        <BreakdownTable title="By provider" columnLabel="Provider" rows={data.providers} />
      </div>
    </div>
  );
}

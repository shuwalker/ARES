import React, { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";

import { apiFetch, readableError } from "@/shared/api-client";
import { useLocalProfile } from "@/shared/local-profile";

interface ReadinessConnection {
    id: string;
    kind: string;
    health: { state: "connected" | "needs_attention" | "offline" };
    capabilities: string[];
}

interface ReadinessResponse {
    profile_ready: boolean;
    connection_ready: boolean;
    execution_available: boolean;
    capabilities: string[];
    profile: string | null;
    connections: ReadinessConnection[];
}

export const ActivationScreen: React.FC = () => {
    const navigate = useNavigate();
    const { profile } = useLocalProfile();
    const [statusText, setStatusText] = useState("Initializing ARES...");
    const [error, setError] = useState<string | null>(null);
    const [attempt, setAttempt] = useState(0);
    const navigationTimer = useRef<number | undefined>(undefined);

    const retry = useCallback(() => {
        if (navigationTimer.current !== undefined) window.clearTimeout(navigationTimer.current);
        setError(null);
        setAttempt((value) => value + 1);
    }, []);

    useEffect(() => {
        const controller = new AbortController();
        const scheduleNavigation = (path: string, delay: number) => {
            navigationTimer.current = window.setTimeout(
                () => navigate(path, { replace: true }),
                delay,
            );
        };

        const checkReadiness = async () => {
            try {
                setStatusText("Checking profile state...");
                const data = await apiFetch<ReadinessResponse>("/api/readiness", {
                    signal: controller.signal,
                });
                if (controller.signal.aborted) return;
                
                if (!data.profile_ready || !profile.displayName.trim()) {
                    setStatusText("Your Local Profile needs attention. Redirecting...");
                    scheduleNavigation("/settings", 600);
                    return;
                }

                // Profile-ready alone is enough to enter the shell. Connection
                // and execution readiness are status signals, not hard gates.
                if (!data.connection_ready || !data.execution_available) {
                    setStatusText(
                        "Profile ready. Opening the Companion (no execution connection yet)...",
                    );
                } else {
                    setStatusText("Execution is available. Opening the Companion...");
                }
                scheduleNavigation("/conversation", 600);
                
            } catch (err: unknown) {
                if (controller.signal.aborted) return;
                setError(readableError(err, "ARES readiness could not be checked."));
            }
        };

        void checkReadiness();
        return () => {
            controller.abort();
            if (navigationTimer.current !== undefined) window.clearTimeout(navigationTimer.current);
        };
    }, [attempt, navigate, profile.displayName]);

    return (
        <div className="flex flex-col items-center justify-center h-screen bg-gray-900 text-white font-mono">
            <div className="max-w-md p-8 border border-gray-700 rounded-lg shadow-xl bg-gray-800 text-center">
                <h1 className="text-2xl font-bold mb-4 tracking-widest text-blue-400">ARES ACTIVATION</h1>
                
                {error ? (
                    <div className="text-red-400 p-4 border border-red-500 rounded bg-red-900/30">
                        <p className="font-bold">Activation Failed</p>
                        <p className="text-sm mt-2">{error}</p>
                        <button 
                            className="mt-4 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-sm"
                            onClick={retry}
                        >
                            Retry
                        </button>
                        <button
                            className="mt-4 ml-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-sm"
                            onClick={() => navigate("/connections", { replace: true })}
                        >
                            Open Connections
                        </button>
                    </div>
                ) : (
                    <div className="flex flex-col items-center">
                        <div className="w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full animate-spin mb-6"></div>
                        <p className="text-lg animate-pulse">{statusText}</p>
                    </div>
                )}
            </div>
        </div>
    );
};

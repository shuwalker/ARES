import { useEffect, useRef, useState, type Dispatch, type SetStateAction } from "react";

import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";


export function useProductState<T extends object>(
  module: string,
  initialState: T,
): [T, Dispatch<SetStateAction<T>>, { loading: boolean; error: string }] {
  const [state, setState] = useState<T>(initialState);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const revision = useRef(0);
  const loaded = useRef(false);
  const skipNextWrite = useRef(false);
  const saveQueue = useRef<Promise<void>>(Promise.resolve());

  useEffect(() => {
    let active = true;
    aresApi.productStateGet<T>(module)
      .then((result) => {
        if (!active) return;
        revision.current = result.revision;
        skipNextWrite.current = true;
        setState(Object.keys(result.state).length > 0 ? result.state : initialState);
        loaded.current = true;
      })
      .catch((cause) => {
        if (active) setError(readableError(cause, `${module} could not be loaded.`));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
    // The module owns its initial shape for the lifetime of the mounted page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [module]);

  useEffect(() => {
    if (!loaded.current) return;
    if (skipNextWrite.current) {
      skipNextWrite.current = false;
      return;
    }
    const timer = window.setTimeout(() => {
      saveQueue.current = saveQueue.current
        .catch(() => undefined)
        .then(async () => {
          const result = await aresApi.productStatePut(module, state, revision.current);
          revision.current = result.revision;
          setError("");
        })
        .catch((cause) => {
          setError(readableError(cause, `${module} changes could not be saved.`));
        });
    }, 250);
    return () => window.clearTimeout(timer);
  }, [module, state]);

  return [state, setState, { loading, error }];
}

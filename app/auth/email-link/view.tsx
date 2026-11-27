"use client";

import { useEffect, useRef, useState } from "react";
import { prepareEmailLink } from "../actions";

export function EmailLink() {
  const started = useRef(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const fragment = new URLSearchParams(window.location.hash.slice(1));
    const types = fragment.getAll("type");
    const tokens = fragment.getAll("token_hash");
    window.history.replaceState(null, "", window.location.pathname);
    if (types.length !== 1 || tokens.length !== 1) {
      setFailed(true);
      return;
    }
    prepareEmailLink(types[0], tokens[0]).then((next) => {
      if (next) window.location.replace(next);
      else setFailed(true);
    }).catch(() => setFailed(true));
  }, []);

  return failed
    ? <p className="auth-error" role="alert">메일에서 링크를 다시 열거나 새 메일을 요청해 주세요.</p>
    : <p className="text-sm text-muted" role="status">이메일 링크를 확인하는 중…</p>;
}

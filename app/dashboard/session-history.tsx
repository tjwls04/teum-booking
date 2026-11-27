"use client";

import { useEffect } from "react";

export function SessionHistory() {
  useEffect(() => {
    function validateRestoredPage(event: PageTransitionEvent) {
      if (event.persisted) window.location.reload();
    }
    window.addEventListener("pageshow", validateRestoredPage);
    return () => window.removeEventListener("pageshow", validateRestoredPage);
  }, []);
  return null;
}

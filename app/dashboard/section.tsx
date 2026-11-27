import styles from "./dashboard.module.css";

export type SavedSearch = { saved?: string | string[] };

export function Heading({ title, description, saved }: { title: string; description?: string; saved?: boolean }) {
  return (
    <header className={styles.heading}>
      <h1 className="section-title">{title}</h1>
      {description && <p className="auth-description">{description}</p>}
      {saved && <p className="auth-notice mt-4" role="status">저장했어요.</p>}
    </header>
  );
}

export function ReadError() {
  return <p className="auth-error" role="alert">설정을 불러오지 못했어요. 새로고침해 주세요.</p>;
}

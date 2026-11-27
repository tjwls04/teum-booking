import { requireShop } from "../../../lib/dashboard/server";
import { maxBookingWindowDays } from "../../../lib/dashboard/settings";
import { savePolicy } from "../actions";
import styles from "../dashboard.module.css";
import { Heading, ReadError } from "../section";
import { Field, SelectField, SettingsForm, TextField } from "../settings-form";

type BankAccount = { bank_name: string; account_number: string; account_holder: string };

export default async function PolicyPage({ searchParams }: PageProps<"/dashboard/policy">) {
  const { supabase, shop } = await requireShop();
  const [{ data: account, error }, { saved }] = await Promise.all([
    supabase.from("shop_bank_accounts").select("bank_name, account_number, account_holder")
      .eq("shop_id", shop.id).maybeSingle<BankAccount>(),
    searchParams,
  ]);

  return (
    <>
      <Heading title="예약 정책" saved={saved === "1"} />
      {error ? <ReadError /> : (
        <SettingsForm key={shop.policy_revision} action={savePolicy} submitLabel="예약 정책 저장">
          <input type="hidden" name="shop" value={shop.id} />
          <input type="hidden" name="revision" value={shop.policy_revision} />
          <fieldset className={styles.group}>
            <legend>예약·취소 기한</legend>
            <div className={styles.fields}>
              <Field label="예약 가능 최소 여유 (분)" name="notice" type="number" min={0} step={1}
                initial={shop.min_notice_minutes} required />
              <Field label="예약 가능 기간 (일)" name="window" type="number" min={1} max={maxBookingWindowDays} step={1}
                initial={shop.booking_window_days} hint="오늘을 포함해 최대 90일까지 설정할 수 있어요." required />
              <Field label="예약 시작 전 취소 기한 (분)" name="cancellationNotice" type="number" min={0} step={1}
                initial={shop.cancellation_notice_minutes} hint="0분이면 예약 시작 전까지 취소할 수 있어요." required />
              <SelectField label="입금 확인 요청 기한" name="report" initial={String(shop.deposit_report_minutes)}
                options={[["30", "30분"], ["60", "60분"], ["120", "120분"]]} />
            </div>
            <TextField label="취소 안내" name="cancellationPolicy" initial={shop.cancellation_policy} />
            <TextField label="예약금 안내" name="depositPolicy" initial={shop.deposit_policy} />
          </fieldset>
          <fieldset className={styles.group}>
            <legend>예약금 입금 계좌</legend>
            <p className="text-sm text-muted">예약금이 있는 시술을 공개하려면 계좌와 위의 안내 두 가지가 모두 필요해요.</p>
            <div className={styles.fields}>
              <Field label="은행" name="bank" initial={account?.bank_name} maxLength={60} />
              <Field label="계좌번호" name="accountNumber" initial={account?.account_number} maxLength={40}
                autoComplete="off" hint="숫자 또는 숫자 사이에 하이픈을 넣어 입력해 주세요." />
              <Field label="예금주" name="accountHolder" initial={account?.account_holder} maxLength={60} />
            </div>
            {account && <p className="text-sm text-muted">계좌를 삭제하려면 세 항목을 모두 비우고 저장하세요.</p>}
          </fieldset>
        </SettingsForm>
      )}
    </>
  );
}

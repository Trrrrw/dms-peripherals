export const controls = {
  dpi: ['setDpi', 'dpi'], pollingRateHz: ['setPollingRate', 'pollingRateHz'],
  dpiStages: ['setDpiStageValue', 'dpiStages'],
  activeDpiStage: ['setActiveDpiStage', 'activeDpiStage'],
  liftOffDistance: ['setLiftOffDistance', 'liftOffDistance'],
  motionSync: ['setMotionSync', 'motionSync'], angleSnapping: ['setAngleSnapping', 'angleSnapping'],
  rippleControl: ['setRippleControl', 'rippleControl'], debounceMs: ['setDebounceTime', 'debounceMs'],
  sleepTimeout: ['setSleepTimeout', 'sleepTimeout'],
};
export function capabilities(client, status) {
  const ui = status.ui || {};
  const hidden = {pollingRateHz: ui.pollingReadOnly, sleepTimeout: ui.hideSleepCard,
    motionSync: ui.hideProcessingCard || ui.hideMotionSync, angleSnapping: ui.hideProcessingCard || ui.hideAngleSnapping,
    rippleControl: ui.hideProcessingCard || ui.hideRippleControl};
  return Object.fromEntries(Object.entries(controls).map(([key, [method, field]]) => [key,
    ui.settingsReady !== false && !hidden[key] && status[field] != null && typeof client[method] === 'function']));
}
export async function applyAndRead(client, before, key, value) {
  if (!capabilities(client, before)[key]) throw new Error('该设备不支持修改此设置');
  if (key === 'dpiStages') {
    if (!value || !Number.isInteger(value.index) || value.index < 0 || value.index >= before.dpiStages.length || !Number.isSafeInteger(value.dpi) || value.dpi < 1 || value.dpi > 100000)
      throw new Error('无效的 DPI 档位');
    await client.setDpiStageValue(value.index, value.dpi);
    const status = await client.readStatus(true);
    if (status.dpiStages?.[value.index] !== value.dpi) throw new Error('DPI 档位回读不一致，请刷新确认');
    return status;
  }
  const bool = ['motionSync', 'angleSnapping', 'rippleControl'].includes(key);
  if (bool ? typeof value !== 'boolean' : key === 'liftOffDistance' ? !['Low', 'High', 'Medium'].includes(value) : !Number.isSafeInteger(value) || value < 0 || value > 100000)
    throw new Error('无效的设置值');
  await client[controls[key][0]](value);
  const status = await client.readStatus(true);
  if (status[controls[key][1]] !== value) throw new Error('已发送设置，但回读结果不一致；请刷新确认设备状态');
  return status;
}

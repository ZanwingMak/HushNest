/** 更新界面示意中的时长，不启动计时器或播放声音。 */
function selectDuration(event) {
  const selected = event.currentTarget;
  document.querySelectorAll('[data-minutes]').forEach(button => button.setAttribute('aria-pressed', String(button === selected)));
  document.getElementById('duration-display').textContent = selected.dataset.minutes;
}
/** 切换官网体验配色，主题不持久化、不读取设备数据。 */
function selectTheme(event) {
  const palettes = {
    forest: ['#f6f5ef', '#213b32', '#285849', '#e6ebe0', '#d4dccf', '#58655b'],
    ocean: ['#f1f6f8', '#233f50', '#235b78', '#e1ebf1', '#cfdee6', '#526672'],
    dusk: ['#f6f2f8', '#43374d', '#69507e', '#eae2f0', '#dbd1e2', '#6e6077'],
    rose: ['#faf2f3', '#50343e', '#8b455b', '#f1e0e5', '#e5ccd4', '#765c65']
  };
  const selected = event.currentTarget;
  ['bg', 'ink', 'accent', 'wash', 'line', 'soft'].forEach((key, index) => document.documentElement.style.setProperty('--' + key, palettes[selected.dataset.theme][index]));
  document.querySelectorAll('[data-theme]').forEach(button => button.setAttribute('aria-pressed', String(button === selected)));
}
document.querySelectorAll('[data-minutes]').forEach(button => button.addEventListener('click', selectDuration));
document.querySelectorAll('[data-theme]').forEach(button => button.addEventListener('click', selectTheme));

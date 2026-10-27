/** mock 用：画一个 128×128 的圆角方块图标（底色 + 白色首字），返回 PNG base64 */
export function mockIcon(name: string, color: string): string {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 128;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(8, 8, 112, 112, 28);
  ctx.fill();
  ctx.fillStyle = '#FFFFFF';
  ctx.font = '600 60px -apple-system, "PingFang SC", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText([...name][0] ?? '?', 64, 68);
  return canvas.toDataURL('image/png').split(',')[1];
}

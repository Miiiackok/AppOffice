import * as THREE from 'three';

const loader = new THREE.TextureLoader();
/** 各向异性过滤上限；OfficeApp 拿到渲染器后设一次，斜着看的看板和地上的图标才不糊 */
let maxAnisotropy = 1;

export function setIconAnisotropy(n: number): void {
  maxAnisotropy = Math.max(1, n);
}

/** Swift 发来的图标 PNG base64 → 贴图（保留 mipmap） */
export function iconTexture(pngBase64: string): THREE.Texture {
  const tex = loader.load(`data:image/png;base64,${pngBase64}`);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = maxAnisotropy;
  return tex;
}

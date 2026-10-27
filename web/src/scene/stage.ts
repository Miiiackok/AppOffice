import * as THREE from 'three';
import { CameraRig } from './camera';
import { PALETTE as P } from './palette';

/** 渲染器、灯光、相机：办公室、画廊、布局预览共用 */
export interface Stage {
  renderer: THREE.WebGLRenderer;
  scene: THREE.Scene;
  rig: CameraRig;
  /** 相机和阴影都对准这块区域 */
  frame(bounds: THREE.Box3): void;
  render(): void;
}

export function createStage(container: HTMLElement): Stage {
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(P.background);
  scene.add(new THREE.HemisphereLight(P.skyLight, P.groundLight, 1.7));
  const sun = new THREE.DirectionalLight(P.sunLight, 1.6);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.bias = -0.0005;
  scene.add(sun, sun.target);

  const rig = new CameraRig();
  const render = () => renderer.render(scene, rig.camera);
  const resize = () => {
    const w = Math.max(1, container.clientWidth), h = Math.max(1, container.clientHeight);
    // 窗口挪到别的屏幕上倍率会变
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(w, h);
    rig.setAspect(w / h);
    // 暂停时改尺寸也要画一帧，不然画布是空的
    render();
  };
  new ResizeObserver(resize).observe(container);
  resize();

  return {
    renderer, scene, rig,
    frame(bounds) {
      rig.fit(bounds);
      const center = bounds.getCenter(new THREE.Vector3());
      const size = bounds.getSize(new THREE.Vector3());
      const r = Math.max(size.x, size.z) * 0.75;
      sun.position.set(center.x - r * 0.4, r * 1.2, center.z + r * 0.6);
      sun.target.position.copy(center);
      const cam = sun.shadow.camera;
      cam.left = -r;
      cam.right = r;
      cam.top = r;
      cam.bottom = -r;
      cam.near = 0.5;
      cam.far = r * 4;
      cam.updateProjectionMatrix();
    },
    render,
  };
}

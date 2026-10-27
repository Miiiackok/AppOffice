import * as THREE from 'three';

/** 俯视角度，约 54° */
const ELEVATION = 0.95;
/** 左右最多转 30° */
const MAX_AZIMUTH = Math.PI / 6;

/** 高角度俯视相机：自动装下整个办公室，可缩放、限角旋转 */
export class CameraRig {
  readonly camera = new THREE.PerspectiveCamera(35, 1, 0.1, 400);
  private readonly center = new THREE.Vector3();
  private radius = 10;
  private zoom = 1;
  private azimuth = 0;

  fit(bounds: THREE.Box3): void {
    bounds.getCenter(this.center);
    this.radius = bounds.getSize(new THREE.Vector3()).length() / 2;
    this.apply();
  }

  setAspect(aspect: number): void {
    this.camera.aspect = aspect;
    this.camera.updateProjectionMatrix();
    this.apply();
  }

  zoomBy(factor: number): void {
    this.zoom = THREE.MathUtils.clamp(this.zoom * factor, 0.3, 1.4);
    this.apply();
  }

  rotateBy(radians: number): void {
    this.azimuth = THREE.MathUtils.clamp(this.azimuth + radians, -MAX_AZIMUTH, MAX_AZIMUTH);
    this.apply();
  }

  reset(): void {
    this.zoom = 1;
    this.azimuth = 0;
    this.apply();
  }

  private apply(): void {
    const vFov = THREE.MathUtils.degToRad(this.camera.fov);
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * this.camera.aspect);
    // 包围球刚好塞进较窄的那个视角；0.8 是因为俯视时深度方向被压扁，可以再近一点
    const distance = (this.radius / Math.sin(Math.min(vFov, hFov) / 2)) * this.zoom * 0.8;
    const horizontal = Math.cos(ELEVATION) * distance;
    this.camera.position.set(
      this.center.x + Math.sin(this.azimuth) * horizontal,
      this.center.y + Math.sin(ELEVATION) * distance,
      this.center.z + Math.cos(this.azimuth) * horizontal,
    );
    this.camera.lookAt(this.center);
  }
}

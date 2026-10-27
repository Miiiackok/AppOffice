import * as THREE from 'three';
import type { Activity } from '../office';
import { PALETTE as P } from './palette';
import { box, textSprite } from './util';

export type Pose = Activity | 'walk' | 'stand' | 'carried';

/** 站着时髋部离地高度（腿 + 鞋） */
const HIP_STAND = 0.4;
/** 坐着时髋部高度，略高于椅面 */
const HIP_SIT = 0.47;

type Prop = 'mug' | 'phone' | 'cookie' | 'laptop' | 'bag' | 'sweat' | 'zzz';

/** zzz 精灵所有小人共用一份贴图和材质，第一次用到时再画 */
let zzzMaterial: THREE.SpriteMaterial | null = null;
const zzzSprite = (): THREE.Sprite => {
  zzzMaterial ??= textSprite('z z z', P.zzz).material;
  return new THREE.Sprite(zzzMaterial);
};

const attach = <T extends THREE.Object3D>(parent: THREE.Object3D, child: T): T => {
  parent.add(child);
  return child;
};

/** 体素小人：方脑袋方身子，原点在脚底，默认面朝 +z */
export class Character {
  readonly root = new THREE.Group();
  private readonly body = new THREE.Group();
  private readonly head = new THREE.Group();
  private readonly armL = new THREE.Group();
  private readonly armR = new THREE.Group();
  private readonly legL = new THREE.Group();
  private readonly legR = new THREE.Group();
  private readonly shirt: THREE.MeshLambertMaterial;
  private readonly badge: THREE.Sprite;
  private readonly props = {} as Record<Prop, THREE.Object3D>;

  constructor(color: string, icon: THREE.Texture | null) {
    this.shirt = new THREE.MeshLambertMaterial({ color });
    this.root.add(this.body);
    // body 的原点在髋部
    this.body.add(box(0.34, 0.4, 0.2, this.shirt, 0, 0, 0));
    this.head.position.set(0, 0.4, 0);
    this.head.add(box(0.32, 0.3, 0.3, P.skin, 0, 0, 0));
    this.head.add(box(0.34, 0.08, 0.32, P.hair, 0, 0.28, 0));
    this.head.add(box(0.34, 0.2, 0.06, P.hair, 0, 0.1, -0.15));
    this.head.add(box(0.05, 0.05, 0.02, P.eye, 0.07, 0.14, 0.15));
    this.head.add(box(0.05, 0.05, 0.02, P.eye, -0.07, 0.14, 0.15));
    this.body.add(this.head);
    for (const [arm, x] of [[this.armL, 0.225], [this.armR, -0.225]] as const) {
      arm.position.set(x, 0.38, 0);
      arm.add(box(0.11, 0.34, 0.11, this.shirt, 0, -0.34, 0));
      arm.add(box(0.1, 0.08, 0.1, P.skin, 0, -0.42, 0));
      this.body.add(arm);
    }
    for (const [leg, x] of [[this.legL, 0.09], [this.legR, -0.09]] as const) {
      leg.position.set(x, 0, 0);
      leg.add(box(0.13, 0.34, 0.14, P.pants, 0, -0.34, 0));
      leg.add(box(0.13, 0.06, 0.18, P.shoe, 0, -0.4, 0.02));
      this.body.add(leg);
    }

    this.props.mug = attach(this.armR, box(0.09, 0.11, 0.09, P.mug, 0, -0.5, 0.07));
    this.props.phone = attach(this.armR, box(0.08, 0.14, 0.02, P.phone, 0, -0.52, 0.07));
    this.props.cookie = attach(this.armR, box(0.09, 0.03, 0.09, P.cookie, 0, -0.48, 0.07));
    const laptop = new THREE.Group();
    laptop.add(box(0.36, 0.02, 0.26, P.laptop, 0, 0, 0));
    const lid = box(0.36, 0.24, 0.02, P.laptop, 0, 0, -0.12);
    lid.rotation.x = -0.25;
    laptop.add(lid);
    laptop.position.set(0, 0.09, 0.28);
    this.props.laptop = attach(this.body, laptop);
    this.props.bag = attach(this.body, box(0.26, 0.3, 0.12, P.bag, 0, 0.04, -0.17));
    this.props.sweat = attach(this.head, box(0.04, 0.07, 0.04, P.sweat, 0.19, 0.2, 0.08));
    const zzz = zzzSprite();
    zzz.scale.set(0.5, 0.125, 1);
    zzz.position.set(0.32, 0.45, 0);
    this.props.zzz = attach(this.head, zzz);

    // 头顶图标压在整个办公室上面画，桌子挡板都挡不住
    this.badge = new THREE.Sprite(new THREE.SpriteMaterial({ map: icon, transparent: true, depthWrite: false, depthTest: false }));
    this.badge.renderOrder = 10;
    this.badge.scale.set(0.45, 0.45, 1);
    this.badge.position.set(0, 0.68, 0);
    this.badge.visible = icon !== null;
    this.head.add(this.badge);
    this.pose('stand', 0);
  }

  setShirt(color: string): void {
    this.shirt.color.set(color);
  }

  setIcon(icon: THREE.Texture | null): void {
    const m = this.badge.material;
    // 贴图真换了才让材质重编译
    if (m.map !== icon) {
      m.map = icon;
      m.needsUpdate = true;
    }
    this.badge.visible = icon !== null;
  }

  /** 头顶图标当前用的贴图 */
  get icon(): THREE.Texture | null {
    return this.badge.material.map;
  }

  /** 释放自己的衣服和图标材质；贴图归 OfficeApp 管，共用的 zzz 不动 */
  dispose(): void {
    this.shirt.dispose();
    this.badge.material.dispose();
  }

  /** t：秒；intensity：0–1，打字快慢；variant：摸鱼花样 0–3 */
  pose(pose: Pose, t: number, intensity = 0, variant = 0): void {
    const { body, head, armL, armR, legL, legR } = this;
    body.position.set(0, HIP_STAND, 0);
    body.rotation.set(0, 0, 0);
    head.rotation.set(0, 0, 0);
    for (const limb of [armL, armR, legL, legR]) limb.rotation.set(0, 0, 0);
    for (const p of Object.values(this.props)) p.visible = false;
    const sin = Math.sin;

    switch (pose) {
      case 'stand':
        break;
      case 'walk':
        this.swing(t * 9, 0.6, 0.03);
        break;
      case 'run':
        this.swing(t * 15, 0.9, 0.06);
        body.rotation.x = 0.15;
        break;
      case 'carried': {
        const s = sin(t * 7) * 0.4;
        legL.rotation.x = s;
        legR.rotation.x = -s;
        armL.rotation.x = -2.7 + s * 0.5;
        armR.rotation.x = -2.7 - s * 0.5;
        break;
      }
      case 'wait':
        // 原地跺脚，抱着胳膊东张西望
        legL.rotation.x = -Math.max(0, sin(t * 8)) * 0.5;
        legR.rotation.x = -Math.max(0, -sin(t * 8)) * 0.5;
        armL.rotation.set(-1.3, 0, -0.5);
        armR.rotation.set(-1.3, 0, 0.5);
        head.rotation.y = sin(t * 1.5) * 0.4;
        break;
      case 'pushup':
        // 身体趴平，手撑地上下起伏
        body.rotation.x = Math.PI / 2 - 0.2;
        body.position.y = 0.3 + (sin(t * 4) * 0.5 + 0.5) * 0.12;
        armL.rotation.x = armR.rotation.x = -Math.PI / 2 + 0.2;
        head.rotation.x = -0.4;
        break;
      case 'eat':
        this.props.cookie.visible = true;
        armR.rotation.x = -2.2 - Math.max(0, sin(t * 3)) * 0.5;
        armL.rotation.x = -0.3;
        head.rotation.x = -0.1 + Math.max(0, sin(t * 3)) * 0.1;
        break;
      case 'type': {
        this.sit();
        const speed = 10 + 30 * intensity;
        armL.rotation.x = -1.15 + sin(t * speed) * 0.12;
        armR.rotation.x = -1.15 + sin(t * speed + 1.7) * 0.12;
        head.rotation.x = 0.1 + sin(t * speed * 0.3) * 0.04 * intensity;
        if (intensity >= 0.8) {
          this.props.sweat.visible = true;
          this.props.sweat.position.y = 0.2 - ((t * 0.8) % 1) * 0.12;
        }
        break;
      }
      case 'boot':
        // 刚到公司：背着包、端着咖啡
        this.sit();
        this.props.bag.visible = true;
        this.props.mug.visible = true;
        armR.rotation.x = -1.2;
        armL.rotation.x = -1.15 + sin(t * 3) * 0.1;
        head.rotation.y = sin(t * 0.7) * 0.3;
        break;
      case 'idle':
        // 半摸鱼：时不时喝口咖啡
        this.sit();
        this.props.mug.visible = true;
        armR.rotation.x = -1.0 - Math.max(0, sin(t * 0.8)) * 1.1;
        armL.rotation.x = -1.15;
        break;
      case 'slack':
        this.sit();
        this.slack(variant % 4, t);
        break;
      case 'toilet':
        this.sit();
        this.props.phone.visible = true;
        armR.rotation.x = -1.3;
        armL.rotation.x = -0.7;
        head.rotation.x = 0.45;
        body.rotation.z = sin(t * 1.3) * 0.04;
        break;
      case 'sofa':
        this.sit();
        this.props.laptop.visible = true;
        armL.rotation.x = -0.75 + sin(t * 11) * 0.08;
        armR.rotation.x = -0.75 + sin(t * 11 + 1.5) * 0.08;
        head.rotation.x = 0.3;
        break;
      case 'arcade':
        // 站在游戏机前：一手摇杆一手狂拍按钮，身子跟着晃
        armL.rotation.set(-1.25 + sin(t * 9) * 0.08, 0, sin(t * 7) * 0.15);
        armR.rotation.x = -1.3 + Math.max(0, sin(t * 18)) * 0.25;
        body.rotation.z = sin(t * 2.3) * 0.06;
        head.rotation.x = -0.05;
        break;
      case 'lounge':
        // 窝在懒人沙发里，手枕在脑后看电视，偶尔笑得一抖一抖
        body.position.y = 0.26;
        body.rotation.x = -0.45;
        legL.rotation.x = legR.rotation.x = -1.25;
        armL.rotation.set(-2.7, 0, 0.5);
        armR.rotation.set(-2.7, 0, -0.5);
        head.rotation.x = 0.3 + Math.max(0, sin(t * 0.9)) * Math.abs(sin(t * 14)) * 0.12;
        break;
      case 'watch':
        // 站在后面看别人打游戏，时不时举手欢呼
        armL.rotation.set(-1.3, 0, -0.5);
        armR.rotation.set(-1.3, 0, 0.5);
        head.rotation.y = sin(t * 0.8) * 0.25;
        if (sin(t * 0.7) > 0.85) {
          armL.rotation.set(-2.9, 0, 0.3);
          armR.rotation.set(-2.9, 0, -0.3);
        }
        break;
    }
  }

  private sit(): void {
    this.body.position.y = HIP_SIT;
    this.legL.rotation.x = this.legR.rotation.x = -Math.PI / 2;
  }

  private swing(phase: number, amount: number, bob: number): void {
    const s = Math.sin(phase) * amount;
    this.legL.rotation.x = s;
    this.legR.rotation.x = -s;
    this.armL.rotation.x = -s * 0.8;
    this.armR.rotation.x = s * 0.8;
    this.body.position.y += Math.abs(Math.sin(phase)) * bob;
  }

  private slack(variant: number, t: number): void {
    const { body, head, armL, armR } = this;
    switch (variant) {
      case 0: // 趴桌睡觉
        body.rotation.x = 0.55;
        armL.rotation.x = armR.rotation.x = -1.7;
        head.rotation.x = 0.35;
        this.props.zzz.visible = true;
        this.props.zzz.position.y = 0.45 + ((t * 0.3) % 1) * 0.15;
        break;
      case 1: // 刷手机
        this.props.phone.visible = true;
        armR.rotation.x = -1.5;
        armL.rotation.x = -1.3;
        head.rotation.x = 0.45;
        break;
      case 2: // 转椅子
        body.rotation.y = t * 2.5;
        armL.rotation.z = 0.7;
        armR.rotation.z = -0.7;
        break;
      default: // 伸懒腰
        armL.rotation.x = armR.rotation.x = -2.9 + Math.sin(t * 2) * 0.15;
        body.rotation.x = -0.1;
        head.rotation.x = -0.25;
        break;
    }
  }
}

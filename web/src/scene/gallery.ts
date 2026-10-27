import * as THREE from 'three';
import { Character, type Pose } from './character';
import { PALETTE as P } from './palette';
import { createStage } from './stage';
import { box, flat, textSprite } from './util';

interface Item { pose: Pose; label: string; seated: boolean; intensity?: number; variant?: number }

const ITEMS: Item[] = [
  { pose: 'stand', label: '站着', seated: false },
  { pose: 'walk', label: '走路', seated: false },
  { pose: 'carried', label: '被拎起来', seated: false },
  { pose: 'wait', label: '排队', seated: false },
  { pose: 'run', label: '跑步机', seated: false },
  { pose: 'pushup', label: '俯卧撑', seated: false },
  { pose: 'eat', label: '吃零食', seated: false },
  { pose: 'type', label: '打字 20%', seated: true, intensity: 0.2 },
  { pose: 'type', label: '打字 100%', seated: true, intensity: 1 },
  { pose: 'boot', label: '刚到公司', seated: true },
  { pose: 'idle', label: '半摸鱼', seated: true },
  { pose: 'slack', label: '睡觉', seated: true, variant: 0 },
  { pose: 'slack', label: '刷手机', seated: true, variant: 1 },
  { pose: 'slack', label: '转椅子', seated: true, variant: 2 },
  { pose: 'slack', label: '伸懒腰', seated: true, variant: 3 },
  { pose: 'toilet', label: '上厕所', seated: true },
  { pose: 'sofa', label: '沙发', seated: true },
  { pose: 'arcade', label: '打游戏机', seated: false },
  { pose: 'lounge', label: '懒人沙发', seated: false },
  { pose: 'watch', label: '围观', seated: false },
];
const SHIRTS = ['#3D7BFD', '#E76F51', '#2A9D8F', '#F2C94C', '#9B51E0'];
const PER_ROW = 6;
const GAP_X = 1.6;
const GAP_Z = 2.1;

/** ?gallery：所有动作排开，检查动画用 */
export function runGallery(container: HTMLElement): void {
  const stage = createStage(container);
  const rows = Math.ceil(ITEMS.length / PER_ROW);
  const width = (PER_ROW - 1) * GAP_X, depth = (rows - 1) * GAP_Z;
  stage.scene.add(flat(box(width + 2, 0.02, depth + 2, P.floor, width / 2, -0.02, depth / 2)));
  const actors = ITEMS.map((item, i) => {
    const x = (i % PER_ROW) * GAP_X, z = Math.floor(i / PER_ROW) * GAP_Z;
    const c = new Character(SHIRTS[i % SHIRTS.length], null);
    c.root.position.set(x, 0, z);
    stage.scene.add(c.root);
    if (item.seated) stage.scene.add(box(0.46, 0.46, 0.46, P.chair, x, 0, z - 0.05));
    const label = textSprite(item.label, P.label);
    label.position.set(x, 1.55, z);
    stage.scene.add(label);
    return { c, item };
  });
  stage.frame(new THREE.Box3(new THREE.Vector3(-0.8, 0, -0.8), new THREE.Vector3(width + 0.8, 1.6, depth + 0.8)));
  const start = performance.now();
  const loop = () => {
    requestAnimationFrame(loop);
    const t = (performance.now() - start) / 1000;
    for (const { c, item } of actors) c.pose(item.pose, t, item.intensity ?? 0, item.variant ?? 0);
    stage.render();
  };
  loop();
}

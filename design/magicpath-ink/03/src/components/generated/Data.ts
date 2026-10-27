export type Entry = { name: string; size: number; kind: string; protected: boolean; count: string };
export const entries: Entry[] = [
  { name: 'node_modules', size: 54.8, kind: 'Node · 依赖', protected: false, count: '12,840' },
  { name: '.venv', size: 32.6, kind: 'Python · 环境', protected: false, count: '7,620' },
  { name: 'target', size: 18.4, kind: 'Rust · 构建', protected: false, count: '2,410' },
  { name: 'dist', size: 11.2, kind: 'Web · 构建', protected: false, count: '1,240' },
  { name: '.git', size: 8.6, kind: '版本历史', protected: true, count: '420' },
  { name: 'Sources', size: 2.8, kind: '源代码', protected: true, count: '150' },
];
export const total = (items: Entry[]) => items.reduce((s, i) => s + i.size, 0);
export const visible = (items: Entry[], query: string, artifacts: boolean) => items.filter(i => i.name.toLowerCase().includes(query.trim().toLowerCase()) && (!artifacts || !i.protected));
export function children(entry: Entry): Entry[] {
  const names = entry.name === 'node_modules' ? ['@vite', '@babel', 'typescript', '@types', '其他依赖'] : ['packages', 'cache', 'lib', 'resources', '其他项目'];
  return names.map((name, i) => ({name, size: entry.size * [.38, .26, .19, .11, .06][i], kind: entry.kind, protected: entry.protected, count: ['4,210', '3,120', '2,408', '1,920', '1,182'][i]}));
}
export const palettes = [
  ['#9e302e', '#284750', '#46413e', '#746249', '#758389', '#a5a5a0'],
  ['#1c514b', '#416e62', '#78988a', '#9bb5a3', '#9f956b', '#c0cbb8'],
  ['#365a73', '#688aa0', '#90a9b7', '#b4c5ce', '#9c937c', '#c6cdd0'],
];
export function ringPath(start: number, end: number, outer: number, inner: number) {
  const p = (angle: number, r: number) => [250 + r * Math.cos(angle), 250 + r * Math.sin(angle)].join(' ');
  const large = end - start > Math.PI ? 1 : 0;
  return `M ${p(start, outer)} A ${outer} ${outer} 0 ${large} 1 ${p(end, outer)} L ${p(end, inner)} A ${inner} ${inner} 0 ${large} 0 ${p(start, inner)} Z`;
}

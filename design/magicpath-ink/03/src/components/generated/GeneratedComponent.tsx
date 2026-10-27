import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { entries, total, visible, children, palettes, ringPath, type Entry } from './Data';
const art = "https://storage.googleapis.com/storage.magicpath.ai/component-assets/465512407113011200/465512407113011201/2430df99e8e0ef3c147599bab818c72274529b361b2643f2a2f93a84a8e327c0.webp";
import './Fonts.css';
import './World.css';
const VARIANT: number = 2;
const worlds = [{
  name: '赤墨 · 断流',
  title: '万象，尽收。',
  subtitle: '循墨而行，见微知著。',
  word: '断流',
  map: '空间图',
  en: 'CRIMSON / INK'
}, {
  name: '青玉 · 回澜',
  title: '一境，万象。',
  subtitle: '山水有界，空间有迹。',
  word: '回澜',
  map: '环形图',
  en: 'JADE / CURRENT'
}, {
  name: '霜蓝 · 云阙',
  title: '层云之下，自有脉络。',
  subtitle: '展卷，见山河。',
  word: '云阙',
  map: '卷页图',
  en: 'MIST / MOUNTAIN'
}];
const w = worlds[VARIANT];
const palette = palettes[VARIANT];
function Icon({
  name,
  size = 18
}: {
  name: string;
  size?: number;
}) {
  const paths: Record<string, ReactNode> = {
    search: <><circle cx="10" cy="10" r="6.5" /><path d="m15 15 5 5" /></>,
    folder: <path d="M3 7V5h6l2 2h10v13H3V7Z" />,
    arrow: <path d="M5 12h14m-6-6 6 6-6 6" />,
    back: <path d="M19 12H5m6-6-6 6 6 6" />,
    refresh: <><path d="M20 8a8 8 0 1 0 0 8M20 3v5h-5" /></>,
    shield: <><path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z" /><path d="m8 12 3 3 5-6" /></>,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 6v6l4 2" /></>,
    grid: <><path d="M3 3h8v11H3zm11 0h7v6h-7zm0 9h7v9h-7zM3 17h8v4H3z" /></>,
    list: <><path d="M8 5h13M8 12h13M8 19h13M3 5h1M3 12h1M3 19h1" /></>,
    close: <path d="m6 6 12 12M18 6 6 18" />,
    chevron: <path d="m9 5 7 7-7 7" />,
    pause: <path d="M8 5v14M16 5v14" />,
    external: <><path d="M14 3h7v7m0-7-11 11M10 4H4v16h16v-6" /></>,
    alert: <><path d="m12 3 10 18H2L12 3Z" /><path d="M12 9v5m0 3v1" /></>
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name] || paths.folder}</svg>;
}
export const GeneratedComponent = () => {
  const [path, setPath] = useState<Entry[]>([]);
  const [selected, setSelected] = useState('node_modules');
  const [query, setQuery] = useState('');
  const [artifacts, setArtifacts] = useState(false);
  const [mapMode, setMapMode] = useState(true);
  const [watching, setWatching] = useState(true);
  const [history, setHistory] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [progress, setProgress] = useState(0);
  const [cancelled, setCancelled] = useState(false);
  const [issues, setIssues] = useState(false);
  const [picker, setPicker] = useState(false);
  const [toast, setToast] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);
  const data = path.length ? children(path[path.length - 1]) : entries;
  const filtered = visible(data, query, artifacts);
  const current = data.find(d => d.name === selected) || data[0];
  const protectedItem = history || current.protected;
  const sum = total(data);
  useEffect(() => {
    if (!scanning) return;
    const id = window.setInterval(() => setProgress(p => Math.min(100, p + 10)), 200);
    return () => window.clearInterval(id);
  }, [scanning]);
  useEffect(() => {
    if (progress === 100) setScanning(false);
  }, [progress]);
  useEffect(() => {
    if (!toast) return;
    const id = window.setTimeout(() => setToast(''), 4000);
    return () => clearTimeout(id);
  }, [toast]);
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault();
        searchRef.current?.focus();
      }
      if (e.key === 'Escape') {
        setPicker(false);
        setIssues(false);
        setQuery('');
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);
  const reset = () => {
    setPath([]);
    setSelected('node_modules');
    setQuery('');
    setArtifacts(false);
  };
  const enter = (entry: Entry) => {
    if (path.length >= 2) {
      setToast('演示已到最深层级');
      return;
    }
    setPath([...path, entry]);
    setSelected(children(entry)[0].name);
    setQuery('');
    setArtifacts(false);
  };
  const back = () => {
    setPath(path.slice(0, -1));
    setSelected(path.length > 1 ? children(path[path.length - 2])[0].name : 'node_modules');
    setQuery('');
  };
  const startScan = () => {
    setProgress(0);
    setCancelled(false);
    setScanning(true);
    setHistory(false);
  };
  const choose = (name: string) => setSelected(name);
  const nav = <div className="breadcrumb"><button onClick={reset}>Workspace</button>{path.map((e, i) => <span key={i}><Icon name="chevron" size={12} /><button onClick={() => {
        setPath(path.slice(0, i + 1));
        setSelected(children(e)[0].name);
      }}>{e.name}</button></span>)}</div>;
  const inspector = <section className="inspector" aria-label="选中项目详情" key={current.name}>
    <div className="detail-top"><span className="small-label">当前选中</span><span className={'protection ' + (protectedItem ? 'is-protected' : '')}><Icon name="shield" size={13} />{protectedItem ? '受保护' : '待核验'}</span></div>
    <h2>{current.name}</h2><p className="detail-path">Workspace{path.map(e => '/' + e.name).join('')}/{current.name}</p>
    <div className="detail-size">{current.size.toFixed(1)}<span>GB</span></div>
    <dl><div><dt>分配空间</dt><dd>{(current.size * .94).toFixed(1)} GB</dd></div><div><dt>包含项目</dt><dd>{current.count}</dd></div></dl>
    <div className="evidence"><strong>{history ? '历史记录 · 已保护' : current.protected ? '关键项目，保留保护' : current.kind}</strong><p>{history ? '记录不代表当前磁盘状态，不自动重新扫描。' : current.protected ? '包含源代码或版本历史，无法视为可再生产物。' : '目录结构与本地规则匹配；是否仍被项目使用尚未确认。'}</p></div>
    <div className="detail-actions"><button className="primary" onClick={() => enter(current)}>进入目录<Icon name="arrow" /></button><button title="在 Finder 中显示（原型演示）" aria-label="在 Finder 中显示（原型演示）" onClick={() => setToast('画布演示：原生应用将在 Finder 中定位所选目录。')}><Icon name="external" /></button></div>
  </section>;
  const table = <section className="directory" aria-label="文件目录">
    <div className="directory-header"><div className="tabs"><button aria-pressed={!artifacts} className={!artifacts ? 'active' : ''} onClick={() => setArtifacts(false)}>全部文件</button><button aria-pressed={artifacts} className={artifacts ? 'active' : ''} onClick={() => setArtifacts(true)}>开发产物</button></div><span>{filtered.length} 个目录</span></div>
    <div className="table-head"><span>名称</span><span>类型</span><span>逻辑大小</span><span /></div>
    <div className="rows">{filtered.length ? filtered.map(e => <div className={'file-row ' + (selected === e.name ? 'selected' : '')} key={e.name}>
      <button className="file-main" onClick={() => choose(e.name)} onDoubleClick={() => enter(e)} aria-pressed={selected === e.name}><span className="filename"><Icon name="folder" /><strong>{e.name}</strong></span><span className="file-kind">{e.kind}</span><span className="file-size">{e.size.toFixed(1)} GB</span></button><button className="row-enter" aria-label={'进入 ' + e.name} onClick={() => enter(e)}><Icon name="chevron" size={14} /></button>
    </div>) : <div className="empty"><Icon name="search" size={24} /><strong>没有匹配的目录</strong><button onClick={() => {
          setQuery('');
          setArtifacts(false);
        }}>清除筛选</button></div>}</div>
  </section>;
  let angle = -Math.PI / 2;
  const map = <div className={'map-space ' + (!mapMode ? 'compact-map' : '')} key={path.map(e => e.name).join('/')}>
    {filtered.length === 0 ? <div className="empty">没有匹配的目录</div> : VARIANT === 1 && mapMode ? <div className="radial-space">
      <svg className="radial" viewBox="0 0 500 500" aria-label="按逻辑大小显示的环形空间图"><circle cx="250" cy="250" r="226" fill="none" stroke="currentColor" strokeWidth=".5" opacity=".35" />
      {filtered.map((e, i) => {
          const start = angle;
          const end = start + e.size / total(filtered) * Math.PI * 2;
          angle = end;
          return <g key={e.name} role="button" tabIndex={0} aria-label={`${e.name} ${e.size.toFixed(1)} GB`} aria-pressed={selected === e.name} onClick={() => choose(e.name)} onDoubleClick={() => enter(e)} onKeyDown={ev => {
            if (ev.key === 'Enter' || ev.key === ' ') {
              ev.preventDefault();
              choose(e.name);
            }
          }} className={selected === e.name ? 'ring-sector chosen' : 'ring-sector'}>
      <path d={ringPath(start + .012, end - .012, selected === e.name ? 213 : 204, 119)} fill={palette[i % 6]} /><path d={ringPath(start + .018, end - .018, 229, 225)} fill={palette[i % 6]} /></g>;
        })}
      <text x="250" y="224" textAnchor="middle" className="ring-label">{path.length ? path[path.length - 1].name : 'Workspace'}</text><text x="250" y="272" textAnchor="middle" className="ring-number">{sum.toFixed(1)}</text><text x="250" y="302" textAnchor="middle" className="ring-unit">GB · 逻辑大小</text></svg>
      <button className="ring-back" disabled={!path.length} onClick={back} aria-label="返回上一级"><Icon name="back" size={16} /></button>
    </div> : <div className={'tiles ' + (VARIANT === 2 && mapMode ? 'folios' : '')}>
      {filtered.map((e, i) => <button key={e.name} className={'tile tile-' + i + (selected === e.name ? ' chosen' : '')} onClick={() => choose(e.name)} onDoubleClick={() => enter(e)} aria-pressed={selected === e.name} style={{
        '--tile': palette[i % 6],
        '--share': e.size / total(filtered),
        '--order': i
      } as CSSProperties}>
      <span className="tile-title"><Icon name="folder" size={17} />{e.name}</span><span className="tile-value">{e.size.toFixed(1)}<small> GB</small></span><span className="tile-type">{e.kind}</span><span className="tile-arrow"><Icon name="arrow" size={20} /></span><span className="tile-stroke" aria-hidden="true" />
      </button>)}
    </div>}
  </div>;
  return <main className={'fs-world world-' + VARIANT} style={{
    '--art': `url(${art})`
  } as CSSProperties}>
    <header className="toolbar"><div className="traffic" aria-hidden="true"><i /><i /><i /></div><a className="brand" href="#" onClick={e => {
        e.preventDefault();
        reset();
      }}><span className="brand-seal">扫</span>FileSweep</a><span className="concept-name">{w.name}</span><div className="toolbar-actions">
    <button className="root-button" onClick={() => setPicker(!picker)} aria-expanded={picker}><Icon name="folder" />选择目录</button><button className="icon-button" onClick={scanning ? () => {
          setScanning(false);
          setCancelled(true);
        } : startScan} aria-label={scanning ? '取消扫描' : '重新扫描演示'} title={scanning ? '取消扫描' : '重新扫描演示'}><Icon name={scanning ? 'close' : 'refresh'} /></button><button className={'icon-button ' + (history ? 'on' : '')} onClick={() => {
          setHistory(!history);
          setWatching(false);
          setScanning(false);
        }} title="切换演示历史记录" aria-label="切换演示历史记录" aria-pressed={history}><Icon name="clock" /></button>
    <label className="search"><Icon name="search" size={16} /><input ref={searchRef} aria-label="搜索目录" placeholder="搜索目录" value={query} onChange={e => setQuery(e.target.value)} />{query ? <button aria-label="清除搜索" onClick={() => setQuery('')}><Icon name="close" size={14} /></button> : <kbd>⌘ F</kbd>}</label></div></header>
    {picker && <div className="root-picker"><strong>选择演示目录</strong><button onClick={() => {
        reset();
        setPicker(false);
        setHistory(false);
        setToast('已选择 Workspace · 演示数据');
      }}><Icon name="folder" />Workspace<span>128.4 GB</span></button><small>画布原型不会访问本机文件。</small></div>}
    <section className="stage">
      <div className="world-art" aria-hidden="true" /><div className="ink-word" aria-hidden="true">{w.word}</div>
      <div className="stage-heading"><div className="heading-copy"><h1>{w.title}</h1><p>{w.subtitle}</p></div><span className="world-seal" aria-hidden="true">墨染<br />江湖</span></div>
      <div className="workspace-heading"><div>{nav}<h2>{path.length ? path[path.length - 1].name : 'Workspace'}<span>{sum.toFixed(1)} <small>GB</small></span></h2></div><div className="map-tools"><button onClick={back} disabled={!path.length} aria-label="返回上一级"><Icon name="back" /></button><div className="segmented"><button aria-pressed={mapMode} onClick={() => setMapMode(true)} className={mapMode ? 'active' : ''}><Icon name="grid" size={15} />{w.map}</button><button aria-pressed={!mapMode} onClick={() => setMapMode(false)} className={!mapMode ? 'active' : ''}><Icon name="list" size={15} />平铺</button></div></div></div>
      <div className="visual-workspace">{VARIANT === 1 && <div className="ring-index"><h3>空间有迹</h3>{filtered.map((e, i) => <button key={e.name} className={selected === e.name ? 'active' : ''} onClick={() => choose(e.name)}><i style={{
              background: palette[i]
            }} /><span>{e.name}</span><b>{(e.size / sum * 100).toFixed(1)}%</b></button>)}<p>弧长对应逻辑大小<br />选中后可进入目录</p></div>}{map}{VARIANT === 1 && inspector}</div>
      <div className="map-caption"><span>{VARIANT === 1 && mapMode ? '弧长按逻辑大小占比' : '目录空间图 · 面积设有下限，非等比'}</span><span>{history ? '历史记录 · 自动更新已停用' : scanning ? `正在扫描 · ${progress}%` : cancelled ? '扫描已取消 · 保留上一快照' : '演示快照 · 24,680 项'}</span></div>
    </section>
    <section className={'lower-workspace ' + (VARIANT === 1 ? 'wide-list' : '')}>{table}{VARIANT !== 1 && inspector}</section>
    <footer className="statusbar"><span className="demo-tag">交互概念 · 演示数据</span><button className="watch-button" onClick={() => setWatching(!watching)} disabled={history} aria-pressed={watching}><span className={'watch-dot ' + (watching && !history ? 'live' : '')} />{watching && !history ? '自动更新' : '更新已暂停'}</button><button className="issue-button" onClick={() => setIssues(!issues)} aria-expanded={issues}><Icon name="alert" size={14} />2 项读取受限 · 1 项跨卷跳过</button><span className="size-note">逻辑大小 ≠ 可回收空间</span></footer>
    {scanning && <div className="scan-line" role="progressbar" aria-label="扫描进度" aria-valuenow={progress} aria-valuemin={0} aria-valuemax={100}><span style={{
        transform: 'scaleX(' + progress / 100 + ')'
      }} /></div>}
    {issues && <aside className="issue-panel"><div><h3>扫描未覆盖全部内容</h3><button onClick={() => setIssues(false)} aria-label="关闭读取问题"><Icon name="close" /></button></div><p><strong>2 项读取受限</strong><br />Private、Shared：权限不足，未读取内容。</p><p><strong>1 项跨卷跳过</strong><br />External：位于所选根目录的另一卷，未扩大范围。</p><small>以上为状态演示，不是本机扫描结果。</small></aside>}
    {toast && <div className="toast" role="status">{toast}</div>}
  </main>;
};
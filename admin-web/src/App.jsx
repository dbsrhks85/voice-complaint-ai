import React, { useEffect, useState, useRef, useCallback } from 'react';
import './index.css';

// ── 환경변수에서 API URL 읽기 (없으면 localhost 폴백) ─────────
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

// ── 카테고리 매핑 (버그 수정: inquiry 등 모든 타입 처리) ───────
const CATEGORY_MAP = {
  repair:        { label: '파손/수리', color: '#ef4444', bg: 'rgba(239,68,68,0.15)',   icon: '🔧' },
  inquiry:       { label: '문의사항', color: '#3b82f6', bg: 'rgba(59,130,246,0.15)',  icon: '❓' },
  suggestion:    { label: '건의사항', color: '#f59e0b', bg: 'rgba(245,158,11,0.15)',  icon: '💡' },
  permission:    { label: '허가/신고', color: '#a855f7', bg: 'rgba(168,85,247,0.15)', icon: '📋' },
  unclassified:  { label: '미분류',   color: '#6b7280', bg: 'rgba(107,114,128,0.15)', icon: '🔍' },
};

const getCat = (category) => CATEGORY_MAP[category] ?? CATEGORY_MAP.unclassified;

// ── 시간 포맷 헬퍼 ─────────────────────────────────────────────
const formatTime = (isoStr) => {
  if (!isoStr) return '-';
  try {
    return new Date(isoStr).toLocaleString('ko-KR', {
      month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit',
    });
  } catch {
    return isoStr;
  }
};

// ── RefreshIcon 컴포넌트 ───────────────────────────────────────
const RefreshIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="23 4 23 10 17 10"/>
    <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
  </svg>
);

// ── 메인 앱 ─────────────────────────────────────────────────────
function App() {
  const { kakao } = window;
  const [reports, setReports]     = useState([]);
  const [loading, setLoading]     = useState(false);
  const [spinning, setSpinning]   = useState(false);
  const mapRef         = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef     = useRef({});

  // ── 민원 데이터 불러오기 ──────────────────────────────────────
  const loadReports = useCallback(async (showSpin = false) => {
    if (showSpin) setSpinning(true);
    setLoading(true);
    try {
      const res  = await fetch(`${API_URL}/get-reports`);
      const data = await res.json();
      setReports(data);
    } catch (err) {
      console.error('민원 목록 로딩 실패:', err);
    } finally {
      setLoading(false);
      if (showSpin) setTimeout(() => setSpinning(false), 600);
    }
  }, []);

  // ── 카카오맵 초기화 ──────────────────────────────────────────
  useEffect(() => {
    if (kakao?.maps) {
      kakao.maps.load(() => {
        if (!mapInstanceRef.current && mapRef.current) {
          const opt = { center: new kakao.maps.LatLng(37.8813, 127.7298), level: 7 };
          mapInstanceRef.current = new kakao.maps.Map(mapRef.current, opt);
        }
        loadReports();
      });
    } else {
      console.error('Kakao Maps SDK가 로드되지 않았습니다.');
    }
    // 30초마다 자동 새로고침
    const interval = setInterval(() => loadReports(), 30_000);
    return () => clearInterval(interval);
  }, [loadReports]);

  // ── 마커 동기화 ───────────────────────────────────────────────
  useEffect(() => {
    if (!mapInstanceRef.current || !kakao) return;
    const map = mapInstanceRef.current;

    // 기존 마커 제거
    Object.values(markersRef.current).forEach(({ marker }) => marker.setMap(null));
    markersRef.current = {};

    reports
      .filter((r) => r.status === 'pending')
      .forEach((report) => {
        const cat   = getCat(report.category);
        const pos   = new kakao.maps.LatLng(report.lat, report.lng);
        const marker = new kakao.maps.Marker({ position: pos });
        marker.setMap(map);

        const iw = new kakao.maps.InfoWindow({
          content: `
            <div style="
              padding:10px 14px;
              font-family:'Noto Sans KR',sans-serif;
              font-size:12px;
              font-weight:600;
              color:#1c2333;
              border-radius:8px;
              min-width:100px;
            ">
              <span style="
                background:${cat.bg};
                color:${cat.color};
                padding:2px 7px;
                border-radius:20px;
                font-size:10px;
                display:inline-block;
                margin-bottom:4px;
              ">${cat.icon} ${cat.label}</span>
              <div>${report.title ?? ''}</div>
            </div>
          `,
        });

        kakao.maps.event.addListener(marker, 'mouseover', () => iw.open(map, marker));
        kakao.maps.event.addListener(marker, 'mouseout',  () => iw.close());
        markersRef.current[report.id] = { marker, pos };
      });
  }, [reports]);

  // ── 처리 완료 ─────────────────────────────────────────────────
  const resolveReport = (id, e) => {
    e.stopPropagation();
    if (!window.confirm('해당 민원을 처리 완료로 변경하시겠습니까?')) return;
    fetch(`${API_URL}/resolve-report/${id}`, { method: 'POST' })
      .then(() => loadReports())
      .catch((err) => console.error('처리 완료 실패:', err));
  };

  // ── 마커 강조 ─────────────────────────────────────────────────
  const handleEnter = (id) => {
    if (!markersRef.current[id] || !kakao) return;
    const redImg = new kakao.maps.MarkerImage(
      'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/marker_red.png',
      new kakao.maps.Size(31, 35),
    );
    markersRef.current[id].marker.setImage(redImg);
    markersRef.current[id].marker.setZIndex(3);
  };

  const handleLeave = (id) => {
    if (!markersRef.current[id] || !kakao) return;
    markersRef.current[id].marker.setImage(null);
    markersRef.current[id].marker.setZIndex(1);
  };

  const handleClick = (id) => {
    if (markersRef.current[id] && mapInstanceRef.current) {
      mapInstanceRef.current.panTo(markersRef.current[id].pos);
    }
  };

  // ── 필터링 ────────────────────────────────────────────────────
  const pending   = reports.filter((r) => r.status === 'pending');
  const completed = reports.filter((r) => r.status === 'completed');

  // ── 렌더링 ────────────────────────────────────────────────────
  return (
    <>
      {/* 로딩 바 */}
      {loading && <div className="loading-bar" style={{ position:'fixed', top:0, left:0, right:0, zIndex:999 }} />}

      {/* 헤더 */}
      <header className="header">
        <div className="header-left">
          <div className="header-logo">🏛️</div>
          <h1>민원 통합 관리 시스템</h1>
        </div>
        <div className="header-stats">
          <div className="stat-chip total">
            📋 전체 {reports.length}
          </div>
          <div className="stat-chip pending">
            🔔 대기 {pending.length}
          </div>
          <div className="stat-chip done">
            ✅ 완료 {completed.length}
          </div>
        </div>
      </header>

      {/* 메인 */}
      <div className="main-container">
        {/* 카카오맵 */}
        <div id="map" ref={mapRef}>
          <div className="map-overlay">
            <span className="auto-refresh-dot" />
            30초마다 자동 갱신 중
          </div>
        </div>

        {/* 사이드바 */}
        <aside className="sidebar">
          <div className="sidebar-header">
            <span className="sidebar-title">민원 목록</span>
            <button
              className={`refresh-btn${spinning ? ' spinning' : ''}`}
              onClick={() => loadReports(true)}
            >
              <RefreshIcon /> 새로고침
            </button>
          </div>

          {/* 대기 중 */}
          <div className="sub-list" style={{ flex: pending.length === 0 ? '0 0 auto' : 1 }}>
            <div className="section-label pending">
              🔔 대기 중인 민원
              <span className="section-count">{pending.length}</span>
            </div>
            <div className="report-list">
              {pending.length === 0 ? (
                <div className="empty-state">
                  <span className="empty-icon">🎉</span>
                  대기 중인 민원이 없습니다
                </div>
              ) : pending.map((report) => {
                const cat = getCat(report.category);
                return (
                  <div
                    key={report.id}
                    className="report-item"
                    onMouseEnter={() => handleEnter(report.id)}
                    onMouseLeave={() => handleLeave(report.id)}
                    onClick={() => handleClick(report.id)}
                  >
                    <div className="card-top">
                      <span
                        className="category-tag"
                        style={{ background: cat.bg, color: cat.color }}
                      >
                        {cat.icon} {cat.label}
                      </span>
                      <span className="card-time">
                        {formatTime(report.created_at)}
                      </span>
                    </div>
                    <div className="card-title">{report.title}</div>
                    <button
                      className="resolve-btn"
                      onClick={(e) => resolveReport(report.id, e)}
                    >
                      ✓ 처리 완료
                    </button>
                  </div>
                );
              })}
            </div>
          </div>

          {/* 처리 완료 */}
          <div className="sub-list">
            <div className="section-label done">
              ✅ 처리 완료
              <span className="section-count">{completed.length} · 10일 후 삭제</span>
            </div>
            <div className="report-list">
              {completed.length === 0 ? (
                <div className="empty-state">
                  <span className="empty-icon">📭</span>
                  완료된 민원이 없습니다
                </div>
              ) : completed.map((report) => {
                const cat = getCat(report.category);
                return (
                  <div
                    key={report.id}
                    className="report-item completed"
                    onClick={() => handleClick(report.id)}
                  >
                    <div className="card-top">
                      <span
                        className="category-tag"
                        style={{ background: cat.bg, color: cat.color }}
                      >
                        {cat.icon} {cat.label}
                      </span>
                      <span className="card-time">
                        {formatTime(report.created_at)}
                      </span>
                    </div>
                    <div className="card-title">{report.title}</div>
                    <div className="resolved-time">
                      🕐 처리: {formatTime(report.resolved_at)}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </aside>
      </div>
    </>
  );
}

export default App;

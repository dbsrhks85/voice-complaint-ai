import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import './index.css';

// ─────────────────────────────────────────
// API
// ─────────────────────────────────────────
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

// ─────────────────────────────────────────
// 민원 카테고리 (사용자 입력 기준)
// ─────────────────────────────────────────
const CATEGORY_MAP = {
  repair: {
    label: '파손/수리',
    color: '#ef4444',
    bg: 'rgba(239,68,68,.14)',
    icon: '🔧',
  },
  inquiry: {
    label: '문의사항',
    color: '#3b82f6',
    bg: 'rgba(59,130,246,.14)',
    icon: '❓',
  },
  suggestion: {
    label: '건의사항',
    color: '#f59e0b',
    bg: 'rgba(245,158,11,.14)',
    icon: '💡',
  },
  permission: {
    label: '허가/신고',
    color: '#8b5cf6',
    bg: 'rgba(139,92,246,.14)',
    icon: '📋',
  },
  unclassified: {
    label: '미분류',
    color: '#64748b',
    bg: 'rgba(100,116,139,.14)',
    icon: '🔍',
  },
};

const getCat = (key) => CATEGORY_MAP[key] ?? CATEGORY_MAP.unclassified;


// ─────────────────────────────────────────
// 실제 담당부서 자동 배정 (Fallback용)
// ─────────────────────────────────────────
function detectDepartment(report, deptRules) {
  const text = `${report.title ?? ''} ${report.address ?? ''}`.toLowerCase();

  for (const [key, dept] of Object.entries(deptRules)) {
    if (key === 'civil') continue;
    if (!dept.keywords) continue;

    if (dept.keywords.some((word) => text.includes(word))) {
      return key;
    }
  }

  // 카테고리 fallback
  if (report.category === 'suggestion') return 'planning';
  if (report.category === 'permission') return 'building';
  if (report.category === 'repair') return 'road';

  return 'civil';
}

// ─────────────────────────────────────────
// 시간
// ─────────────────────────────────────────
const formatTime = (isoStr) => {
  if (!isoStr) return '-';

  try {
    return new Date(isoStr).toLocaleString('ko-KR', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return isoStr;
  }
};

// ─────────────────────────────────────────
// 아이콘
// ─────────────────────────────────────────
const SearchIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
    <circle cx="11" cy="11" r="8" stroke="currentColor" strokeWidth="2" />
    <line x1="21" y1="21" x2="16.65" y2="16.65" stroke="currentColor" strokeWidth="2" />
  </svg>
);

// ─────────────────────────────────────────
// 앱
// ─────────────────────────────────────────
function App() {
  const { kakao } = window;

  const [statusFilter, setStatusFilter] = useState('pending'); // 'pending' or 'completed'
  const [reports, setReports] = useState([]);
  const [departments, setDepartments] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [departmentFilter, setDepartmentFilter] = useState('all');
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [loading, setLoading] = useState(false);

  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef({});

  // 부서 규칙 (Key-Value 맵)
  const deptRules = useMemo(() => {
    const map = {};
    if (Array.isArray(departments)) {
      departments.forEach((d) => {
        map[d.key] = d;
      });
    }
    return map;
  }, [departments]);

  // 부서 로드
  const loadDepartments = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/get-departments`);
      if (!res.ok) throw new Error('API response not ok');
      const data = await res.json();
      if (Array.isArray(data)) {
        setDepartments(data);
      } else {
        throw new Error('Data is not an array');
      }
    } catch (e) {
      console.error('부서 로드 실패 (기본값 사용):', e);
      // 서버에서 부서 정보를 못 가져올 경우 기본 부서 세팅
      setDepartments([
        { key: 'road', label: '도로과', icon: '🛣️', color: '#3b82f6', tasks: ['도로 보수', '포트홀 처리'] },
        { key: 'building', label: '건축과', icon: '🏢', color: '#8b5cf6', tasks: ['건물 안전점검', '불법건축 단속'] },
        { key: 'park', label: '녹지공원과', icon: '🌳', color: '#10b981', tasks: ['공원 관리', '가로수 정비'] },
        { key: 'traffic', label: '교통과', icon: '🚦', color: '#f59e0b', tasks: ['교통 시설물 수리', '불법주차 단속'] },
        { key: 'environment', label: '환경과', icon: '♻️', color: '#ef4444', tasks: ['쓰레기 무단투기 단속', '소음 측정'] },
        { key: 'planning', label: '기획예산과', icon: '📊', color: '#6366f1', tasks: ['민원 정책 반영', '예산 검토'] },
        { key: 'civil', label: '민원담당관', icon: '🤝', color: '#64748b', tasks: ['일반 상담', '부서 배정'] },
      ]);
    }
  }, []);

  // 민원 로드
  const loadReports = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch(`${API_URL}/get-reports`);
      const data = await res.json();
      setReports(data);
    } catch (e) {
      console.error('민원 로드 실패:', e);
    } finally {
      setLoading(false);
    }
  }, []);

  // 지도 init
  useEffect(() => {
    if (!kakao?.maps) return;

    kakao.maps.load(() => {
      if (!mapInstanceRef.current && mapRef.current) {
        mapInstanceRef.current = new kakao.maps.Map(mapRef.current, {
          center: new kakao.maps.LatLng(37.8813, 127.7298),
          level: 7,
        });
      }

      loadDepartments();
      loadReports();
    });
  }, [kakao, loadDepartments, loadReports]);

  // 데이터 가공
  const processedReports = useMemo(() => {
    return reports.map((r) => {
      // DB에 저장된 부서 정보가 있으면 사용, 없으면 자동 배정 시도
      let deptKey = r.department;
      if (!deptKey || !deptRules[deptKey]) {
        deptKey = detectDepartment(r, deptRules);
      }

      return {
        ...r,
        deptKey,
        dept: deptRules[deptKey] || { label: '미분류', icon: '❓', color: '#64748b', tasks: [] },
      };
    });
  }, [reports, deptRules]);

  // 부서 목록
  const departmentMenus = useMemo(() => {
    const counts = {};

    processedReports
      .filter((r) => r.status === 'pending')
      .forEach((r) => {
        counts[r.deptKey] = (counts[r.deptKey] || 0) + 1;
      });

    return departments.map((d) => ({
      ...d,
      count: counts[d.key] || 0,
    }));
  }, [processedReports, departments]);

  // 필터링된 민원 목록
  const filteredReports = useMemo(() => {
    return processedReports.filter((r) => {
      // 1. 상태 필터 (pending / completed)
      if (r.status !== statusFilter) return false;

      // 2. 부서 필터
      const matchDept =
        departmentFilter === 'all' || r.deptKey === departmentFilter;

      // 3. 검색 필터
      const q = searchQuery.toLowerCase();
      const matchSearch =
        !q ||
        r.title?.toLowerCase().includes(q) ||
        r.address?.toLowerCase().includes(q);

      return matchDept && matchSearch;
    });
  }, [processedReports, statusFilter, departmentFilter, searchQuery]);

  // 지도 마커
  useEffect(() => {
    if (!mapInstanceRef.current || !kakao) return;

    const map = mapInstanceRef.current;

    Object.values(markersRef.current).forEach((m) =>
      m.marker.setMap(null)
    );

    markersRef.current = {};

    filteredReports.forEach((report) => {
      const pos = new kakao.maps.LatLng(report.lat, report.lng);

      const marker = new kakao.maps.Marker({
        position: pos,
      });

      marker.setMap(map);

      const info = new kakao.maps.InfoWindow({
        content: `
          <div style="padding:12px 14px;min-width:230px;">
            <div style="font-weight:700;margin-bottom:6px;">
              ${report.title ?? ''}
            </div>

            <div style="font-size:12px;color:#475569;margin-bottom:8px;">
              📍 ${report.address ?? ''}
            </div>

            <div style="
              background:#f1f5f9;
              padding:8px;
              border-radius:10px;
              font-size:12px;
            ">
              담당부서: ${report.dept.label}
            </div>
          </div>
        `,
      });

      kakao.maps.event.addListener(marker, 'mouseover', () =>
        info.open(map, marker)
      );

      kakao.maps.event.addListener(marker, 'mouseout', () =>
        info.close()
      );

      markersRef.current[report.id] = { marker, pos };
    });
  }, [filteredReports, kakao]);



  // 처리완료
  const resolveReport = async (id) => {
    if (!window.confirm('해당 민원을 처리 완료하시겠습니까?')) return;

    const formData = new FormData();
    formData.append('status', 'completed');

    try {
      const res = await fetch(`${API_URL}/update-status/${id}`, {
        method: 'POST',
        body: formData,
      });
      if (res.ok) {
        loadReports();
      } else {
        alert('상태 업데이트에 실패했습니다.');
      }
    } catch (e) {
      console.error('상태 업데이트 에러:', e);
    }
  };

  const moveToMarker = (id) => {
    const target = markersRef.current[id];
    if (!target || !mapInstanceRef.current) return;

    mapInstanceRef.current.panTo(target.pos);
  };

  return (
    <>
      {loading && <div className="loading-bar" />}

      {/* 헤더 */}
      <header className="header">
        <div className="header-left">
          <button
            className="menu-btn"
            onClick={() => setSidebarOpen((v) => !v)}
          >
            ☰
          </button>

          <div className="header-logo">🏛️</div>
          <h1 className="header-title">
            민원 통합 관리 시스템
          </h1>
        </div>

        <div className="header-stats">
          <div className="stat-chip total">
            전체 {reports.length}
          </div>

          <div className="stat-chip pending">
            목록 {filteredReports.length}
          </div>
        </div>
      </header>

      {/* 본문 */}
      <div className="main-container">
        {/* 지도 */}
        <div id="map" ref={mapRef}>
          <div className="map-overlay">
            실제 처리 부서 기준 운영 중
          </div>
        </div>

        {/* 사이드바 */}
        <aside className={`sidebar${sidebarOpen ? '' : ' sidebar--hidden'}`}>
          {/* 검색 */}
          <div className="sidebar-search">
            <div className="search-input-wrap">
              <SearchIcon />

              <input
                className="search-input"
                placeholder="제목 / 주소 검색"
                value={searchQuery}
                onChange={(e) =>
                  setSearchQuery(e.target.value)
                }
              />
            </div>
          </div>

          {/* 부서 필터 */}
          <div className="sidebar-filters">
            <button
              className={`filter-chip ${departmentFilter === 'all' ? 'active' : ''
                }`}
              onClick={() => setDepartmentFilter('all')}
            >
              전체
            </button>

            {departmentMenus.map((dept) => (
              <button
                key={dept.key}
                className={`filter-chip ${departmentFilter === dept.key ? 'active' : ''
                  }`}
                onClick={() =>
                  setDepartmentFilter(dept.key)
                }
              >
                {dept.icon} {dept.label} ({dept.count})
              </button>
            ))}
          </div>

          {/* 상태 필터 탭 */}
          <div className="status-tabs">
            <button 
              className={`status-tab ${statusFilter === 'pending' ? 'active' : ''}`}
              onClick={() => setStatusFilter('pending')}
            >
              대기 중
            </button>
            <button 
              className={`status-tab ${statusFilter === 'completed' ? 'active' : ''}`}
              onClick={() => setStatusFilter('completed')}
            >
              처리 완료
            </button>
          </div>

          {/* 목록 */}
          <div className="report-list">
            {filteredReports.map((report) => {
              const cat = getCat(report.category);

              return (
                <div
                  key={report.id}
                  className="report-item"
                  onClick={() => moveToMarker(report.id)}
                >
                  {/* 상단 */}
                  <div className="card-top">
                    <span
                      className="category-tag"
                      style={{
                        background: cat.bg,
                        color: cat.color,
                      }}
                    >
                      {cat.icon} {cat.label}
                    </span>

                    <span className="card-time">
                      {formatTime(report.created_at)}
                    </span>
                  </div>

                  {/* 제목 */}
                  <p className="card-title">
                    {report.title}
                  </p>

                  {/* 실제 부서 */}
                  <div className="department-box">
                    <span className="dept-label">
                      담당 부서
                    </span>

                    <span className="dept-name">
                      {report.dept.icon} {report.dept.label}
                    </span>
                  </div>

                  {/* 위치 */}
                  <div className="card-address">
                    📍 {report.address || '위치 정보 없음'}
                  </div>

                  {/* 업무 */}
                  <div className="task-box">
                    <div className="task-title">
                      처리 업무
                    </div>

                    {(report.dept.tasks || []).map((task, idx) => (
                      <div
                        className="task-row"
                        key={idx}
                      >
                        • {task}
                      </div>
                    ))}
                  </div>

                  {/* 버튼 (대기 중일 때만 표시) */}
                  {report.status === 'pending' && (
                    <button
                      className="resolve-btn"
                      onClick={(e) => {
                        e.stopPropagation();
                        resolveReport(report.id);
                      }}
                    >
                      처리 완료
                    </button>
                  )}
                  
                  {/* 처리 완료 라벨 (완료 상태일 때 표시) */}
                  {report.status === 'completed' && (
                    <div className="resolved-label">
                      ✅ 처리 완료됨 ({formatTime(report.resolved_at)})
                    </div>
                  )}
                </div>
              );
            })}

            {filteredReports.length === 0 && (
              <div className="empty-state">
                표시할 민원이 없습니다.
              </div>
            )}
          </div>
        </aside>
      </div>
    </>
  );
}

export default App;
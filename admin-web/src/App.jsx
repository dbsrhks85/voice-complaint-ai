import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, 
  PieChart, Pie, Cell, Legend 
} from 'recharts';
import { fetchEventSource } from '@microsoft/fetch-event-source';
import './index.css';

// ─────────────────────────────────────────
// API
// ─────────────────────────────────────────
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';
const ADMIN_API_KEY = import.meta.env.VITE_ADMIN_API_KEY || '';
const ADMIN_ACCESS_TOKEN_KEY = 'adminAccessToken';
const adminHeaders = (accessToken) => ({
  ...(ADMIN_API_KEY ? { 'X-Admin-Api-Key': ADMIN_API_KEY } : {}),
  ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
});

// ─────────────────────────────────────────
// 민원 카테고리 (사용자 입력 기준)
// ─────────────────────────────────────────
// ─────────────────────────────────────────
// 민원 유형 (현장 / 비현장)
// ─────────────────────────────────────────
const TYPE_MAP = {
  field: {
    label: '현장 민원',
    color: '#3b82f6',
    bg: 'rgba(59,130,246,.14)',
    icon: '📍',
  },
  admin: {
    label: '비현장/행정',
    color: '#8b5cf6',
    bg: 'rgba(139,92,246,.14)',
    icon: '🏢',
  },
};

const getType = (type) => TYPE_MAP[type] ?? TYPE_MAP.field;


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

  const [authChecked, setAuthChecked] = useState(false);
  const [accessToken, setAccessToken] = useState(
    () => localStorage.getItem(ADMIN_ACCESS_TOKEN_KEY) || ''
  );
  const [admin, setAdmin] = useState(null);
  const [loginForm, setLoginForm] = useState({ username: '', password: '' });
  const [loginError, setLoginError] = useState('');
  const [loginLoading, setLoginLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState('pending'); // 'pending' or 'completed'
  const [reports, setReports] = useState([]);
  const [departments, setDepartments] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [departmentFilter, setDepartmentFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all'); // 'all' | 'field' | 'admin'
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [loading, setLoading] = useState(false);
  const [selectedReport, setSelectedReport] = useState(null);
  const [rejectingReportId, setRejectingReportId] = useState(null);
  const [rejectionReason, setRejectionReason] = useState('접수 내용이 부족합니다');
  const [customReason, setCustomReason] = useState('');
  const [activeView, setActiveView] = useState('dashboard'); // 'dashboard' | 'departments' | 'stats'
  const [stats, setStats] = useState(null);
  const [statsLoading, setStatsLoading] = useState(false);
  const [newDept, setNewDept] = useState({
    key: '',
    label: '',
    phone: '',
    color: '#3b82f6',
    keywords: '',
    tasks: ''
  });
  const [addingDept, setAddingDept] = useState(false);
  const [deletingDept, setDeletingDept] = useState(null);
  const [reassignKey, setReassignKey] = useState('');
  const [affectedReports, setAffectedReports] = useState([]);
  const [highlightedReportId, setHighlightedReportId] = useState(null);

  const resetFilters = () => {
    setStatusFilter('pending');
    setDepartmentFilter('all');
    setTypeFilter('all');
    setSearchQuery('');
    setHighlightedReportId(null);
  };

  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef({});

  const clearAdminSession = useCallback(() => {
    localStorage.removeItem(ADMIN_ACCESS_TOKEN_KEY);
    setAccessToken('');
    setAdmin(null);
    setReports([]);
    setSelectedReport(null);
  }, []);

  const handleUnauthorized = useCallback(() => {
    clearAdminSession();
    setLoginError('로그인이 만료되었습니다. 다시 로그인해주세요.');
  }, [clearAdminSession]);

  const adminFetch = useCallback(async (path, options = {}) => {
    const headers = {
      ...adminHeaders(accessToken),
      ...(options.headers || {}),
    };
    const res = await fetch(`${API_URL}${path}`, {
      ...options,
      headers,
    });
    if (res.status === 401 || res.status === 403) {
      handleUnauthorized();
      throw new Error(`HTTP ${res.status}`);
    }
    return res;
  }, [accessToken, handleUnauthorized]);

  const handleLogin = async (event) => {
    event.preventDefault();
    if (loginLoading) return;

    setLoginLoading(true);
    setLoginError('');
    try {
      const formData = new FormData();
      formData.append('username', loginForm.username.trim());
      formData.append('password', loginForm.password);

      const res = await fetch(`${API_URL}/admin/auth/login`, {
        method: 'POST',
        body: formData,
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.detail || '로그인에 실패했습니다.');
      }

      localStorage.setItem(ADMIN_ACCESS_TOKEN_KEY, data.access_token);
      setAccessToken(data.access_token);
      setAdmin(data.admin);
      setLoginForm({ username: '', password: '' });
    } catch (e) {
      setLoginError(e.message || '로그인에 실패했습니다.');
    } finally {
      setLoginLoading(false);
    }
  };

  const handleLogout = async () => {
    try {
      if (accessToken) {
        await fetch(`${API_URL}/admin/auth/logout`, {
          method: 'POST',
          headers: adminHeaders(accessToken),
        });
      }
    } catch (e) {
      console.warn('관리자 로그아웃 요청 실패:', e);
    } finally {
      clearAdminSession();
    }
  };

  useEffect(() => {
    if (!accessToken) {
      setAuthChecked(true);
      return;
    }

    let cancelled = false;
    fetch(`${API_URL}/admin/auth/me`, {
      headers: adminHeaders(accessToken),
    })
      .then(async (res) => {
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`);
        if (!cancelled) setAdmin(data.admin);
      })
      .catch(() => {
        if (!cancelled) clearAdminSession();
      })
      .finally(() => {
        if (!cancelled) setAuthChecked(true);
      });

    return () => {
      cancelled = true;
    };
  }, [accessToken, clearAdminSession]);

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
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
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
    if (!accessToken) return;
    setLoading(true);
    try {
      const res = await adminFetch('/get-reports');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setReports(Array.isArray(data) ? data : []);
    } catch (e) {
      console.error('민원 로드 실패:', e);
      setReports([]);
    } finally {
      setLoading(false);
    }
  }, [accessToken, adminFetch]);

  // 통계 데이터 로드
  const loadStats = useCallback(async () => {
    if (!accessToken) return;
    setStatsLoading(true);
    try {
      const res = await adminFetch('/admin/stats');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setStats(data);
    } catch (e) {
      console.error('통계 로드 실패:', e);
    } finally {
      setStatsLoading(false);
    }
  }, [accessToken, adminFetch]);

  useEffect(() => {
    if (activeView === 'stats') {
      loadStats();
    }
  }, [activeView, loadStats]);

  // 지도 init
  useEffect(() => {
    if (!authChecked || !accessToken || !admin || !kakao?.maps) return;

    kakao.maps.load(() => {
        if (!mapInstanceRef.current && mapRef.current) {
          mapInstanceRef.current = new kakao.maps.Map(mapRef.current, {
            center: new kakao.maps.LatLng(37.8813, 127.7298),
            level: 7,
          });

          // 지도 클릭 시 선택 해제
          kakao.maps.event.addListener(mapInstanceRef.current, 'click', () => {
            setHighlightedReportId(null);
          });
        }

      loadDepartments();
      loadReports();
    });
  }, [kakao, loadDepartments, loadReports, authChecked, accessToken, admin]);

  // SSE 실시간 갱신 수신
  useEffect(() => {
    if (!authChecked || !accessToken || !admin) return;

    const controller = new AbortController();
    
    fetchEventSource(`${API_URL}/admin/events`, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: controller.signal,
      onmessage(event) {
        if (event.event === 'new_complaint') {
          console.log('[sse] 새 민원 접수 이벤트 수신 - 목록 갱신');
          loadReports();
        }
      },
      onerror(err) {
        console.warn('[sse] 연결 오류 발생, 자동 재연결 대기...', err);
        // 에러가 나도 자동으로 재연결을 시도함 (fetchEventSource 기본 동작)
      }
    });

    return () => {
      console.log('[sse] 컴포넌트 언마운트 - 연결 종료');
      controller.abort();
    };
  }, [authChecked, accessToken, admin, loadReports]);

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
      .filter((r) => r.status === statusFilter)
      .forEach((r) => {
        counts[r.deptKey] = (counts[r.deptKey] || 0) + 1;
      });

    return departments.map((d) => ({
      ...d,
      count: counts[d.key] || 0,
    }));
  }, [processedReports, departments, statusFilter]);

  // 필터링된 민원 목록
  const filteredReports = useMemo(() => {
    return processedReports.filter((r) => {
      // 1. 상태 필터 (pending / completed)
      if (r.status !== statusFilter) return false;

      // 2. 부서 필터
      const matchDept =
        departmentFilter === 'all' || r.deptKey === departmentFilter;

      // 3. 유형 필터 (현장 / 비현장)
      const matchType = 
        typeFilter === 'all' || r.complaint_type === typeFilter;

      // 4. 검색 필터
      const q = searchQuery.toLowerCase();
      const matchSearch =
        !q ||
        r.title?.toLowerCase().includes(q) ||
        r.address?.toLowerCase().includes(q);

      return matchDept && matchType && matchSearch;
    });
  }, [processedReports, statusFilter, departmentFilter, typeFilter, searchQuery]);

  // 지도 마커
  useEffect(() => {
    if (!mapInstanceRef.current || !kakao) return;

    const map = mapInstanceRef.current;

    Object.values(markersRef.current).forEach((m) =>
      m.marker.setMap(null)
    );

    markersRef.current = {};

    filteredReports.forEach((report) => {
      if (report.lat == null || report.lng == null) return;

      const lat = Number(report.lat);
      const lng = Number(report.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

      const pos = new kakao.maps.LatLng(lat, lng);
      
      // 마커 이미지 설정 (선택된 마커는 다른 이미지)
      const isHighlighted = report.id === highlightedReportId;
      let markerImage = null;
      if (isHighlighted) {
        const imageSrc = "https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/markerStar.png"; 
        const imageSize = new kakao.maps.Size(24, 35); 
        markerImage = new kakao.maps.MarkerImage(imageSrc, imageSize);
      }

      const marker = new kakao.maps.Marker({
        position: pos,
        image: markerImage,
        zIndex: isHighlighted ? 100 : 1
      });

      marker.setMap(map);

      // 마커 클릭 시: 해당 민원의 상태/유형/부서 필터 자동 조정 및 리스트 스크롤
      kakao.maps.event.addListener(marker, 'click', () => {
        setHighlightedReportId(report.id);
        
        // 1. 필터 자동 조정
        setStatusFilter(report.status);
        setTypeFilter(report.complaint_type);
        setDepartmentFilter(report.deptKey);
        
        // 2. 리스트 스크롤 (필터 적용 후 렌더링 시간을 고려해 약간의 지연 후 실행)
        setTimeout(() => {
          const el = document.getElementById(`report-${report.id}`);
          if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
        }, 100);
      });

      markersRef.current[report.id] = { marker, pos };
    });
  }, [filteredReports, kakao, highlightedReportId]);



  // 상태 변경 (수락, 완료, 반려 공통)
  const updateStatus = async (id, status, reason = null) => {
    const formData = new FormData();
    formData.append('status', status);
    if (reason) formData.append('rejection_reason', reason);

    try {
      const res = await fetch(`${API_URL}/update-status/${id}`, {
        method: 'POST',
        headers: adminHeaders(accessToken),
        body: formData,
      });
      if (res.ok) {
        loadReports();
        setRejectingReportId(null);
        setCustomReason('');
      } else {
        throw new Error(`HTTP ${res.status}`);
      }
    } catch (e) {
      console.error('상태 업데이트 에러:', e);
      window.alert('상태 변경에 실패했습니다.');
    }
  };

  // 처리완료 (기존 호환성 유지용)
  const resolveReport = (id) => {
    if (!window.confirm('해당 민원을 처리 완료하시겠습니까?')) return;
    updateStatus(id, 'completed');
  };

  const moveToMarker = (id) => {
    const target = markersRef.current[id];
    if (!target || !mapInstanceRef.current) return;

    mapInstanceRef.current.panTo(target.pos);
  };

  const downloadAllAttachments = async (reportId) => {
    try {
      const res = await adminFetch(`/download-attachments/${reportId}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `report-${reportId}-attachments.zip`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error('첨부파일 다운로드 실패:', e);
      window.alert('첨부파일 다운로드에 실패했습니다.');
    }
  };

  const handleAddDepartment = async (e) => {
    e.preventDefault();
    if (!newDept.key || !newDept.label) return window.alert('키와 부서명은 필수입니다.');
    
    setAddingDept(true);
    try {
      const formData = new FormData();
      Object.entries(newDept).forEach(([k, v]) => formData.append(k, v));
      
      const res = await fetch(`${API_URL}/admin/add-department`, {
        method: 'POST',
        headers: adminHeaders(accessToken),
        body: formData
      });
      
      if (res.ok) {
        await loadDepartments();
        setNewDept({ key: '', label: '', phone: '', color: '#3b82f6', keywords: '', tasks: '' });
        window.alert('부서가 추가되었습니다.');
      } else {
        const err = await res.json();
        throw new Error(err.detail || '추가 실패');
      }
    } catch (e) {
      console.error(e);
      window.alert(`오류: ${e.message}`);
    } finally {
      setAddingDept(false);
    }
  };

  const handleDeleteDepartment = (dept) => {
    const others = departments.filter(d => d.id !== dept.id);
    if (others.length === 0) {
      window.alert("최소 하나의 부서는 운영되어야 합니다. 삭제 전 다른 부서를 먼저 추가해 주세요.");
      return;
    }

    const affected = processedReports.filter(r => r.department === dept.key);
    
    if (affected.length === 0) {
      if (window.confirm(`'${dept.label}' 부서를 삭제하시겠습니까?`)) {
        setDeletingDept(dept);
        setReassignKey(others[0].key); // 실제로는 민원이 없어도 API 구조상 필요할 수 있음
        // 아래 confirmDelete를 직접 호출하거나 간단한 삭제 API 호출
        setTimeout(() => {
           setDeletingDept(dept);
           setReassignKey(others[0].key);
           confirmDelete(); 
        }, 0);
      }
      return;
    }

    setAffectedReports(affected);
    setDeletingDept(dept);
    setReassignKey(others[0].key);
  };

  const confirmDelete = async () => {
    if (!deletingDept || !reassignKey) return;

    try {
      setLoading(true);
      const res = await fetch(`${API_URL}/admin/delete-department/${deletingDept.id}?reassign_to=${reassignKey}`, {
        method: 'DELETE',
        headers: adminHeaders(accessToken),
      });
      if (res.ok) {
        await loadDepartments();
        await loadReports();
        setDeletingDept(null);
        setAffectedReports([]);
        window.alert('부서가 삭제되고 관련 민원이 재배정되었습니다.');
      } else {
        const err = await res.json();
        window.alert(`삭제 실패: ${err.detail}`);
      }
    } catch (e) {
      console.error('부서 삭제 오류:', e);
    } finally {
      setLoading(false);
    }
  };

  if (!authChecked) {
    return (
      <div className="auth-page">
        <div className="auth-loading">관리자 세션을 확인하는 중입니다.</div>
      </div>
    );
  }

  if (!accessToken || !admin) {
    return (
      <div className="auth-page">
        <form className="auth-panel" onSubmit={handleLogin}>
          <div className="auth-logo">🏛️</div>
          <h1 className="auth-title">관리자 로그인</h1>
          <p className="auth-subtitle">발급된 관리자 계정으로만 접근할 수 있습니다.</p>

          <label className="auth-field">
            <span>아이디</span>
            <input
              value={loginForm.username}
              onChange={(e) =>
                setLoginForm((prev) => ({ ...prev, username: e.target.value }))
              }
              autoComplete="username"
              autoFocus
            />
          </label>

          <label className="auth-field">
            <span>비밀번호</span>
            <input
              type="password"
              value={loginForm.password}
              onChange={(e) =>
                setLoginForm((prev) => ({ ...prev, password: e.target.value }))
              }
              autoComplete="current-password"
            />
          </label>

          {loginError && <div className="auth-error">{loginError}</div>}

          <button className="auth-submit" type="submit" disabled={loginLoading}>
            {loginLoading ? '로그인 중' : '로그인'}
          </button>
        </form>
      </div>
    );
  }

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

          <nav className="header-nav">
            <button 
              className={`nav-item ${activeView === 'dashboard' ? 'active' : ''}`}
              onClick={() => setActiveView('dashboard')}
            >
              민원 현황
            </button>
            <button 
              className={`nav-item ${activeView === 'departments' ? 'active' : ''}`}
              onClick={() => setActiveView('departments')}
            >
              부서 관리
            </button>
            <button 
              className={`nav-item ${activeView === 'stats' ? 'active' : ''}`}
              onClick={() => setActiveView('stats')}
            >
              통계 분석
            </button>
          </nav>
        </div>

        <div className="header-stats">
          <div className="stat-chip total">
            전체 {reports.length}
          </div>

          <div className="stat-chip pending">
            목록 {filteredReports.length}
          </div>

          <button className="logout-btn" onClick={handleLogout}>
            로그아웃
          </button>
        </div>
      </header>

      {/* 본문 */}
      <div className="main-container">
        {/* 통계 뷰 */}
        {activeView === 'stats' && (
          <div className="stats-view">
            <div className="stats-header">
              <h2>민원 통계 분석</h2>
              <p>실시간으로 집계된 민원 접수 및 처리 현황입니다.</p>
            </div>

            {statsLoading ? (
              <div className="stats-loading">데이터를 불러오는 중...</div>
            ) : stats ? (
              <>
                <div className="stats-summary-grid">
                  <div className="summary-card">
                    <span className="label">대기 중</span>
                    <span className="value pending">{stats.summary.pending}</span>
                  </div>
                  <div className="summary-card">
                    <span className="label">처리 중</span>
                    <span className="value processing">{stats.summary.processing}</span>
                  </div>
                  <div className="summary-card">
                    <span className="label">완료됨</span>
                    <span className="value completed">{stats.summary.completed}</span>
                  </div>
                  <div className="summary-card">
                    <span className="label">반려됨</span>
                    <span className="value rejected">{stats.summary.rejected}</span>
                  </div>
                </div>

                <div className="charts-grid">
                  <div className="chart-container">
                    <h3>오늘의 민원 접수 추이</h3>
                    <div style={{ width: '100%', height: 300 }}>
                      <ResponsiveContainer>
                        <AreaChart data={stats.today_trend}>
                          <defs>
                            <linearGradient id="colorCount" x1="0" y1="0" x2="0" y2="1">
                              <stop offset="5%" stopColor="#3a6ea5" stopOpacity={0.3}/>
                              <stop offset="95%" stopColor="#3a6ea5" stopOpacity={0}/>
                            </linearGradient>
                          </defs>
                          <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                          <XAxis dataKey="hour" axisLine={false} tickLine={false} tick={{fontSize: 12, fill: '#64748b'}} />
                          <YAxis axisLine={false} tickLine={false} tick={{fontSize: 12, fill: '#64748b'}} />
                          <Tooltip 
                            contentStyle={{borderRadius: '12px', border: 'none', boxShadow: '0 4px 12px rgba(0,0,0,0.1)'}}
                          />
                          <Area type="monotone" dataKey="count" stroke="#3a6ea5" strokeWidth={3} fillOpacity={1} fill="url(#colorCount)" />
                        </AreaChart>
                      </ResponsiveContainer>
                    </div>
                  </div>

                  <div className="chart-container">
                    <h3>부서별 민원 비중</h3>
                    <div style={{ width: '100%', height: 300 }}>
                      <ResponsiveContainer>
                        <PieChart>
                          <Pie
                            data={stats.dept_distribution}
                            cx="50%"
                            cy="50%"
                            innerRadius={60}
                            outerRadius={100}
                            paddingAngle={5}
                            dataKey="value"
                          >
                            {stats.dept_distribution.map((entry, index) => (
                              <Cell key={`cell-${index}`} fill={['#3b82f6', '#8b5cf6', '#10b981', '#f59e0b', '#ef4444', '#6366f1', '#64748b'][index % 7]} />
                            ))}
                          </Pie>
                          <Tooltip 
                            contentStyle={{borderRadius: '12px', border: 'none', boxShadow: '0 4px 12px rgba(0,0,0,0.1)'}}
                          />
                          <Legend verticalAlign="bottom" height={36}/>
                        </PieChart>
                      </ResponsiveContainer>
                    </div>
                  </div>
                </div>
              </>
            ) : (
              <div className="stats-error">통계 데이터를 불러올 수 없습니다.</div>
            )}
          </div>
        )}

        {/* 대시보드 뷰 */}
        <div className={`dashboard-view-wrapper ${activeView === 'dashboard' ? '' : 'hidden'}`}>
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

              {/* 상태 필터 */}
              <div className="sidebar-status-wrap">
                <div className="status-menu">
                  <button 
                    className={`status-menu-item ${statusFilter === 'pending' ? 'active' : ''}`}
                    onClick={() => setStatusFilter('pending')}
                  >
                    접수 중
                  </button>
                  <button 
                    className={`status-menu-item ${statusFilter === 'processing' ? 'active' : ''}`}
                    onClick={() => setStatusFilter('processing')}
                  >
                    처리 중
                  </button>
                  <button 
                    className={`status-menu-item ${statusFilter === 'completed' ? 'active' : ''}`}
                    onClick={() => setStatusFilter('completed')}
                  >
                    처리 완료
                  </button>
                  <button 
                    className={`status-menu-item ${statusFilter === 'rejected' ? 'active' : ''}`}
                    onClick={() => setStatusFilter('rejected')}
                  >
                    반려됨
                  </button>
                </div>
              </div>

              {/* 유형 필터 */}
              <div className="sidebar-filters type-filters">
                <button
                  className={`filter-chip ${typeFilter === 'all' ? 'active' : ''}`}
                  onClick={() => setTypeFilter('all')}
                >
                  전체 유형
                </button>
                <button
                  className={`filter-chip ${typeFilter === 'field' ? 'active' : ''}`}
                  onClick={() => setTypeFilter('field')}
                >
                  현장 민원
                </button>
                <button
                  className={`filter-chip ${typeFilter === 'admin' ? 'active' : ''}`}
                  onClick={() => setTypeFilter('admin')}
                >
                  비현장/행정
                </button>
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
                    {dept.label} ({dept.count})
                  </button>
                ))}
              </div>


              {/* 목록 */}
              <div className="report-list">
                {filteredReports.map((report) => {
                  const type = getType(report.complaint_type);

                  return (
                    <div
                      key={report.id}
                      id={`report-${report.id}`}
                      className={`report-item ${highlightedReportId === report.id ? 'highlighted' : ''}`}
                      onClick={() => {
                        setHighlightedReportId(report.id);
                        moveToMarker(report.id);
                      }}
                    >
                      {/* 상단 */}
                      <div className="card-top">
                        <span
                          className="category-tag"
                          style={{
                            background: type.bg,
                            color: type.color,
                          }}
                        >
                          {type.label}
                        </span>

                        <span className="card-time">
                          {formatTime(report.created_at)}
                        </span>
                      </div>

                      {/* 작성자 정보 */}
                      <div className="card-user-info">
                        <span className="user-nickname">
                          👤 {report.user_label || report.nickname || '사용자'}
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
                          {report.dept.label}
                          {report.dept.phone && <span className="dept-phone-small"> ({report.dept.phone})</span>}
                        </span>
                      </div>

                      {/* 위치 */}
                      <div className="card-address">
                        📍 {report.address || '위치 정보 없음'}
                      </div>

                      {/* 첨부파일 요약 */}
                      {report.attachment_urls?.length > 0 && (
                        <div className="card-attachments-summary">
                          📎 첨부파일: {report.attachment_urls[0].split(/[\\/]/).pop()}
                          {report.attachment_urls.length > 1 && ` 외 ${report.attachment_urls.length - 1}건`}
                        </div>
                      )}

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

                      {/* 하단 버튼 영역 */}
                      <div className="card-actions">
                        <button
                          className="detail-view-btn"
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedReport(report);
                          }}
                        >
                          자세히
                        </button>

                        {report.status === 'pending' && (
                          <>
                            <button
                              className="accept-btn"
                              onClick={(e) => {
                                e.stopPropagation();
                                updateStatus(report.id, 'processing');
                              }}
                            >
                              수락
                            </button>
                            <button
                              className="reject-btn"
                              onClick={(e) => {
                                e.stopPropagation();
                                setRejectingReportId(report.id);
                              }}
                            >
                              반려
                            </button>
                          </>
                        )}

                        {report.status === 'processing' && (
                          <button
                            className="resolve-btn"
                            onClick={(e) => {
                              e.stopPropagation();
                              updateStatus(report.id, 'completed');
                            }}
                          >
                            완료 처리
                          </button>
                        )}
                      </div>

                      {/* 반려 사유 입력 오버레이 */}
                      {rejectingReportId === report.id && (
                        <div className="rejection-overlay" onClick={(e) => e.stopPropagation()}>
                          <div className="rejection-title">민원 반려 사유 선택</div>
                          <select 
                            className="rejection-select"
                            value={rejectionReason}
                            onChange={(e) => setRejectionReason(e.target.value)}
                          >
                            <option value="접수 내용이 부족합니다">접수 내용이 부족합니다</option>
                            <option value="위치 정보가 누락되었습니다">위치 정보가 누락되었습니다</option>
                            <option value="관할 구역이 아닙니다">관할 구역이 아닙니다</option>
                            <option value="기타">기타(직접작성)</option>
                          </select>

                          {rejectionReason === '기타' && (
                            <textarea 
                              className="rejection-input"
                              placeholder="반려 사유를 직접 입력해주세요."
                              value={customReason}
                              onChange={(e) => setCustomReason(e.target.value)}
                            />
                          )}

                          <div className="rejection-actions">
                            <button className="rejection-cancel-btn" onClick={() => setRejectingReportId(null)}>취소</button>
                            <button 
                              className="rejection-confirm-btn" 
                              onClick={() => updateStatus(report.id, 'rejected', rejectionReason === '기타' ? customReason : rejectionReason)}
                            >
                              반려 확정
                            </button>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}

                {filteredReports.length === 0 && (
                  <div className="empty-state">
                    검색 결과가 없습니다.
                  </div>
                )}
            </div>
          </aside>
        </div>

        {/* 부서 관리 뷰 */}
        {activeView === 'departments' && (
          <div className="dept-manager-view">
            <div className="dept-manager-header">
              <h2 className="view-title">부서 및 AI 분류 관리</h2>
              <p className="view-subtitle">새로운 부서를 추가하면 AI가 자동으로 민원을 해당 부서로 분류하기 시작합니다.</p>
            </div>

            <div className="dept-manager-content">
              {/* 추가 폼 */}
              <div className="dept-form-card">
                <h3 className="card-inner-title">새 부서 추가</h3>
                <form className="dept-form" onSubmit={handleAddDepartment}>
                  <div className="form-row">
                    <label>
                      <span>부서 코드 (Key)</span>
                      <input 
                        placeholder="예: tax, health" 
                        value={newDept.key}
                        onChange={e => setNewDept({...newDept, key: e.target.value})}
                      />
                    </label>
                    <label>
                      <span>부서명 (Label)</span>
                      <input 
                        placeholder="예: 세무과" 
                        value={newDept.label}
                        onChange={e => setNewDept({...newDept, label: e.target.value})}
                      />
                    </label>
                  </div>
                  <div className="form-row">
                    <label>
                      <span>대표 전화번호</span>
                      <input 
                        placeholder="예: 02-123-4567" 
                        value={newDept.phone}
                        onChange={e => setNewDept({...newDept, phone: e.target.value})}
                      />
                    </label>
                    <label>
                      <span>테마 색상</span>
                      <div className="color-input-group">
                        <input 
                          type="color" 
                          value={newDept.color}
                          onChange={e => setNewDept({...newDept, color: e.target.value})}
                        />
                        <span className="hex-code">{newDept.color.toUpperCase()}</span>
                      </div>
                    </label>
                  </div>
                  <label>
                    <span>AI 분류 키워드 (쉼표 구분)</span>
                    <textarea 
                      placeholder="예: 세금, 지방세, 환급, 고지서, 연체" 
                      value={newDept.keywords}
                      onChange={e => setNewDept({...newDept, keywords: e.target.value})}
                    />
                  </label>
                  <label>
                    <span>주요 처리 업무 (쉼표 구분)</span>
                    <textarea 
                      placeholder="예: 지방세 상담 및 안내, 환급금 조회 및 신청" 
                      value={newDept.tasks}
                      onChange={e => setNewDept({...newDept, tasks: e.target.value})}
                    />
                  </label>
                  <button className="dept-submit-btn" type="submit" disabled={addingDept}>
                    {addingDept ? '추가 중...' : '부서 등록 및 AI 프롬프트 갱신'}
                  </button>
                </form>
              </div>

              {/* 리스트 */}
              <div className="dept-list-card">
                <h3 className="card-inner-title">현재 운영 부서 목록</h3>
                <div className="dept-table-wrap" style={{ maxHeight: '450px', overflowY: 'auto' }}>
                  <table className="dept-table">
                    <thead>
                      <tr>
                        <th>부서명</th>
                        <th>코드</th>
                        <th>전화번호</th>
                        <th>키워드</th>
                        <th>작업</th>
                      </tr>
                    </thead>
                    <tbody>
                      {departments.map(dept => (
                        <tr key={dept.id}>
                          <td className="td-label" style={{color: dept.color, fontWeight: 700}}>{dept.label}</td>
                          <td className="td-key"><code>{dept.key}</code></td>
                          <td className="td-phone">{dept.phone || '-'}</td>
                          <td className="td-keywords">
                            {(dept.keywords || []).map((k, idx) => (
                              <span key={idx} className="keyword-chip">{k}</span>
                            ))}
                            {(dept.keywords || []).length === 0 && (
                              <span className="text-muted" style={{fontSize: '11px'}}>키워드 없음</span>
                            )}
                          </td>
                          <td className="td-actions">
                            <button 
                              className="dept-del-btn"
                              onClick={() => handleDeleteDepartment(dept)}
                            >
                              삭제
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 민원 상세 모달 */}
      {selectedReport && (
        <div className="modal-overlay" onClick={() => setSelectedReport(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-title-area">
                <span className="modal-category">
                  {getType(selectedReport.complaint_type).label}
                </span>
                <h2 className="modal-title">{selectedReport.title}</h2>
              </div>
              <button className="modal-close" onClick={() => setSelectedReport(null)}>✕</button>
            </div>

            <div className="modal-body">
              <section className="modal-section">
                <h3 className="section-title">작성자 정보</h3>
                <div className="info-grid">
                  <div className="info-item">
                    <span className="info-label">민원인</span>
                    <span className="info-value">
                      {selectedReport.user_label || selectedReport.nickname || '사용자'}
                    </span>
                  </div>
                  <div className="info-item">
                    <span className="info-label">접수 일시</span>
                    <span className="info-value">{formatTime(selectedReport.created_at)}</span>
                  </div>
                  <div className="info-item">
                    <span className="info-label">민원 유형</span>
                    <span className="info-value">{selectedReport.complaint_type === 'field' ? '현장 민원' : '행정/비현장'}</span>
                  </div>
                  <div className="info-item">
                    <span className="info-label">담당 부서</span>
                    <span className="info-value">
                      {selectedReport.dept.label}
                      {selectedReport.dept.phone && ` (${selectedReport.dept.phone})`}
                    </span>
                  </div>
                </div>
              </section>

              <section className="modal-section">
                <h3 className="section-title">민원 내용 (원본 텍스트)</h3>
                <div className="stt-text-box">
                  {selectedReport.stt_text || "내용이 없습니다."}
                </div>
              </section>

              <section className="modal-section">
                <h3 className="section-title">상세 주소</h3>
                <div className="address-box">
                  📍 {selectedReport.address || "주소 정보 없음"}
                </div>
              </section>

              <section className="modal-section">
                <div className="section-header-flex">
                  <h3 className="section-title">첨부 파일 ({selectedReport.attachment_urls?.length || 0})</h3>
                  {selectedReport.attachment_urls?.length > 0 && (
                    <button 
                      className="download-all-btn"
                      onClick={() => downloadAllAttachments(selectedReport.id)}
                    >
                      📦 전체 다운로드 (ZIP)
                    </button>
                  )}
                </div>
                
                {selectedReport.attachment_urls?.length > 0 ? (
                  <div className="attachment-grid">
                    {selectedReport.attachment_urls.map((url, idx) => {
                      const fileName = url.split(/[\\/]/).pop();
                      const fileUrl = url.startsWith('http') ? url : `${API_URL}/uploads/${fileName}`;
                      const isImage = /\.(jpg|jpeg|png|gif|webp)$/i.test(fileName);

                      return (
                        <div key={idx} className="attachment-item">
                          {isImage ? (
                            <div className="attachment-preview" onClick={() => window.open(fileUrl, '_blank')}>
                              <img src={fileUrl} alt={`attachment-${idx}`} />
                            </div>
                          ) : (
                            <div className="attachment-file-icon" onClick={() => window.open(fileUrl, '_blank')}>
                              📄
                            </div>
                          )}
                          <span className="attachment-name" title={fileName}>{fileName}</span>
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <div className="no-attachments">첨부파일이 없습니다.</div>
                )}
              </section>
            </div>

            <div className="modal-footer">
              {selectedReport.status === 'pending' ? (
                <button 
                  className="modal-resolve-btn"
                  onClick={() => {
                    updateStatus(selectedReport.id, 'processing');
                    setSelectedReport(null);
                  }}
                >
                  민원 수락 (처리 시작)
                </button>
              ) : (
                <div className="modal-resolved-badge" style={{
                  background: selectedReport.status === 'rejected' ? 'rgba(239,68,68,0.08)' : 
                              selectedReport.status === 'processing' ? 'rgba(59,130,246,0.08)' : 'rgba(16,185,129,0.08)',
                  color: selectedReport.status === 'rejected' ? '#ef4444' : 
                         selectedReport.status === 'processing' ? '#2563eb' : '#047857'
                }}>
                  {selectedReport.status === 'processing' ? '⚙️ 처리 중으로 변경됨' : 
                   selectedReport.status === 'rejected' ? '❌ 반려됨' : '✅ 처리 완료됨'}
                  {' '}({formatTime(selectedReport.resolved_at)})
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* 부서 삭제 및 재배정 모달 (고아 민원 방지) */}
      {deletingDept && affectedReports.length > 0 && (
        <div className="modal-overlay" onClick={() => setDeletingDept(null)}>
          <div className="modal-content delete-modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2 className="modal-title">⚠️ 부서 삭제 및 잔류 민원 이관</h2>
              <button className="modal-close" onClick={() => setDeletingDept(null)}>✕</button>
            </div>
            <div className="modal-body">
              <p className="delete-warning">
                <strong>{deletingDept.label}</strong> 부서를 삭제하려고 합니다.<br/>
                현재 이 부서에 담당자가 없는 <strong>{affectedReports.length}건</strong>의 민원이 존재합니다.
              </p>
              
              <div className="affected-list-wrap">
                <label>이관 대상 민원 ({affectedReports.length}건)</label>
                <div className="affected-scroll">
                  {affectedReports.map(r => (
                    <div key={r.id} className="affected-item">
                      <span className="affected-id">#{r.id}</span>
                      <span className="affected-title">{r.title}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="reassign-select-wrap">
                <label>이관 대상 부서 선택</label>
                <select 
                  value={reassignKey} 
                  onChange={e => setReassignKey(e.target.value)}
                  className="reassign-select"
                >
                  {departments
                    .filter(d => d.id !== deletingDept.id)
                    .map(d => (
                      <option key={d.key} value={d.key}>{d.label}</option>
                    ))
                  }
                </select>
              </div>
            </div>
            <div className="modal-footer">
              <button className="cancel-btn" onClick={() => setDeletingDept(null)}>취소</button>
              <button className="confirm-delete-btn" onClick={confirmDelete}>
                {affectedReports.length}건 이관 및 부서 삭제
              </button>
            </div>
          </div>
        </div>
      )}
    </>

  );
}

export default App;

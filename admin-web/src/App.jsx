import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import './index.css';

// ─────────────────────────────────────────
// API
// ─────────────────────────────────────────
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';
const ADMIN_API_KEY = import.meta.env.VITE_ADMIN_API_KEY || '';
const adminHeaders = () =>
  ADMIN_API_KEY ? { 'X-Admin-Api-Key': ADMIN_API_KEY } : {};

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
  const [selectedReport, setSelectedReport] = useState(null);
  const [rejectingReportId, setRejectingReportId] = useState(null);
  const [rejectionReason, setRejectionReason] = useState('접수 내용이 부족합니다');
  const [customReason, setCustomReason] = useState('');

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
    setLoading(true);
    try {
      const res = await fetch(`${API_URL}/get-reports`, {
        headers: adminHeaders(),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setReports(Array.isArray(data) ? data : []);
    } catch (e) {
      console.error('민원 로드 실패:', e);
      setReports([]);
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
      if (report.lat == null || report.lng == null) return;

      const lat = Number(report.lat);
      const lng = Number(report.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

      const pos = new kakao.maps.LatLng(lat, lng);

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



  // 상태 변경 (수락, 완료, 반려 공통)
  const updateStatus = async (id, status, reason = null) => {
    const formData = new FormData();
    formData.append('status', status);
    if (reason) formData.append('rejection_reason', reason);

    try {
      const res = await fetch(`${API_URL}/update-status/${id}`, {
        method: 'POST',
        headers: adminHeaders(),
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
                      {report.dept.icon} {report.dept.label}
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
                        <button 
                          className="rejection-confirm-btn"
                          onClick={() => {
                            const reason = rejectionReason === '기타' ? customReason : rejectionReason;
                            updateStatus(report.id, 'rejected', reason);
                          }}
                        >
                          반려 확정
                        </button>
                        <button 
                          className="rejection-cancel-btn"
                          onClick={() => setRejectingReportId(null)}
                        >
                          취소
                        </button>
                      </div>
                    </div>
                  )}
                  
                  {/* 처리 완료 라벨 (완료 상태일 때 표시) */}
                  {report.status === 'completed' && (
                    <div className="resolved-label">
                      ✅ 처리 완료됨 ({formatTime(report.resolved_at)})
                    </div>
                  )}

                  {/* 반려 라벨 */}
                  {report.status === 'rejected' && (
                    <div className="resolved-label" style={{ color: '#ef4444', background: 'rgba(239,68,68,0.08)' }}>
                      ❌ 반려됨: {report.rejection_reason}
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

      {/* 민원 상세 모달 */}
      {selectedReport && (
        <div className="modal-overlay" onClick={() => setSelectedReport(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-title-area">
                <span className="modal-category">
                  {getCat(selectedReport.category).icon} {getCat(selectedReport.category).label}
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
                      onClick={() => window.open(`${API_URL}/download-attachments/${selectedReport.id}`, '_blank')}
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
    </>

  );
}

export default App;

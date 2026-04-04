import React, { useEffect, useState, useRef } from 'react';

function App() {
  const { kakao } = window;
  const [reports, setReports] = useState([]);
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef({});

  const redSrc = 'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/marker_red.png';

  const loadReports = () => {
    fetch('http://127.0.0.1:8000/get-reports')
      .then((res) => res.json())
      .then((data) => {
        setReports(data);
      })
      .catch((err) => console.error('Failed to load reports', err));
  };

  useEffect(() => {
    // 1. 지도 초기화 (카카오맵 스크립트가 로드되었는지 확인)
    if (kakao && kakao.maps) {
      kakao.maps.load(() => {
        if (!mapInstanceRef.current && mapRef.current) {
          const mapOption = { center: new kakao.maps.LatLng(37.8813, 127.7298), level: 3 };
          mapInstanceRef.current = new kakao.maps.Map(mapRef.current, mapOption);
        }
        loadReports();
      });
    } else {
        // 스크립트가 로드되기 전에 컴포넌트 마운트 될 경우 대비
        console.error("Kakao maps script is not loaded");
    }
  }, []);

  useEffect(() => {
    if (!mapInstanceRef.current || !kakao) return;
    const map = mapInstanceRef.current;

    // 기존 마커 초기화
    Object.values(markersRef.current).forEach((markerObj) => {
      markerObj.marker.setMap(null);
    });
    markersRef.current = {};

    // 데이터가 변할 때마다 마커 새로 생성
    reports.forEach((report) => {
      if (report.status === 'pending') {
        const markerPos = new kakao.maps.LatLng(report.lat, report.lng);
        const marker = new kakao.maps.Marker({
          position: markerPos,
        });
        marker.setMap(map);

        const iw = new kakao.maps.InfoWindow({
          content: `<div style="padding:5px;font-size:12px;">${report.title}</div>`,
        });

        kakao.maps.event.addListener(marker, 'mouseover', () => iw.open(map, marker));
        kakao.maps.event.addListener(marker, 'mouseout', () => iw.close());

        markersRef.current[report.id] = { marker, markerPos };
      }
    });
  }, [reports]);

  const resolveReport = (id, event) => {
    event.stopPropagation();
    if (window.confirm('해당 민원을 처리 완료하시겠습니까?')) {
      // url typo 5500 -> 8000 (backend) 맞게 수정됨
      fetch(`http://127.0.0.1:8000/resolve-report/${id}`, { method: 'POST' })
        .then(() => loadReports())
        .catch((err) => console.error('Failed to resolve report', err));
    }
  };

  const handleMouseEnter = (id) => {
    if (markersRef.current[id] && kakao) {
      const redImg = new kakao.maps.MarkerImage(redSrc, new kakao.maps.Size(31, 35));
      markersRef.current[id].marker.setImage(redImg);
      markersRef.current[id].marker.setZIndex(3);
    }
  };

  const handleMouseLeave = (id) => {
    if (markersRef.current[id] && kakao) {
      markersRef.current[id].marker.setImage(null);
      markersRef.current[id].marker.setZIndex(1);
    }
  };

  const handleItemClick = (id) => {
    if (markersRef.current[id] && mapInstanceRef.current) {
      mapInstanceRef.current.panTo(markersRef.current[id].markerPos);
    }
  };

  const pendingReports = reports.filter((r) => r.status === 'pending');
  const completedReports = reports.filter((r) => r.status === 'completed');

  return (
    <>
      <div className="header">
        <h1>민원 통합 관리 시스템</h1>
      </div>
      <div className="main-container">
        <div id="map" ref={mapRef}></div>
        <div className="sidebar">
          <div className="sub-list" id="pending-list">
            <h3>🔔 대기 중인 민원</h3>
            {pendingReports.map((report) => (
              <div
                key={report.id}
                className="report-item"
                onMouseEnter={() => handleMouseEnter(report.id)}
                onMouseLeave={() => handleMouseLeave(report.id)}
                onClick={() => handleItemClick(report.id)}
              >
                <span
                  className="category-tag"
                  style={{ background: report.category === 'repair' ? '#e74c3c' : '#f1c40f' }}
                >
                  {report.category === 'repair' ? '파손/수리' : '건의사항'}
                </span>
                <div style={{ fontWeight: 'bold', fontSize: '15px' }}>{report.title}</div>
                <button
                  className="resolve-btn"
                  onClick={(e) => resolveReport(report.id, e)}
                >
                  처리 완료
                </button>
              </div>
            ))}
          </div>
          <div className="sub-list" id="completed-list">
            <h3>✅ 처리 완료 (10일 후 삭제)</h3>
            {completedReports.map((report) => (
              <div
                key={report.id}
                className="report-item"
                onClick={() => handleItemClick(report.id)}
              >
                <span
                  className="category-tag"
                  style={{ background: report.category === 'repair' ? '#e74c3c' : '#f1c40f' }}
                >
                  {report.category === 'repair' ? '파손/수리' : '건의사항'}
                </span>
                <div style={{ fontWeight: 'bold', fontSize: '15px' }}>{report.title}</div>
                <div className="resolved-time">해결 시각: {report.resolved_at}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}

export default App;

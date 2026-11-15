/* Shared behaviour for every page: header/footer, reveal, count-up, bar charts, lightbox, toggles. No dependencies. */
(function () {
  'use strict';

  var REPO = 'https://github.com/qmarcusv/DBMS_TA_Group2';
  var PAGES = [
    ['index.html', 'Overview', 'home'],
    ['data.html', '1 · Data', 'data'],
    ['indexing.html', '2 · Index', 'indexing'],
    ['optimizer.html', '3 · Optimizer', 'optimizer'],
    ['transactions.html', '4 · Transactions', 'transactions'],
    ['concurrency.html', '5 · Concurrency', 'concurrency'],
    ['team.html', 'Team', 'team'],
    ['reproduce.html', 'Reproduce', 'reproduce']
  ];

  var page = document.body.getAttribute('data-page') || 'home';

  /* ---------- header ---------- */
  var header = document.getElementById('site-header');
  if (header) {
    var links = PAGES.map(function (p) {
      return '<a href="' + p[0] + '"' + (p[2] === page ? ' class="active"' : '') + '>' + p[1] + '</a>';
    }).join('');
    header.className = 'site-header';
    header.innerHTML =
      '<div class="container bar">' +
      '<a class="brand" href="index.html"><img src="assets/img/logo-hcmut.png" alt="HCMUT logo">' +
      '<span>Clinical MRI · DBMS<small>CO3021 · Group 02 · HCMUT</small></span></a>' +
      '<nav class="nav" aria-label="Main">' + links + '</nav></div>';
    var active = header.querySelector('.nav a.active');
    var navEl = header.querySelector('.nav');
    if (active && navEl && navEl.scrollWidth > navEl.clientWidth) { navEl.scrollLeft = Math.max(0, active.offsetLeft - navEl.clientWidth / 2); }
  }

  /* ---------- footer ---------- */
  var footer = document.getElementById('site-footer');
  if (footer) {
    footer.className = 'site-footer';
    footer.innerHTML =
      '<div class="container"><div class="cols">' +
      '<div><h4>Read in this order</h4><p>1 · This website (summary)<br>2 · <a href="report.pdf">Full report (PDF)</a><br>3 · <a href="' + REPO + '">GitHub repository</a></p></div>' +
      '<div><h4>The project</h4><p>Workload-driven evaluation of Microsoft SQL Server 2025 on 48,345 lumbar-spine MRI slices.</p></div>' +
      '<div><h4>Course</h4><p>CO3021 – Database Management Systems<br>Ho Chi Minh City University of Technology (HCMUT)<br>Instructor: PhD. Phan Trong Nhan</p></div>' +
      '</div><small>Every number on this site was measured in SQL Server Management Studio on the project database; the scripts are in the repository.</small></div>';
  }

  /* ---------- reveal on scroll ---------- */
  var reveals = [].slice.call(document.querySelectorAll('.reveal'));
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { threshold: 0.12 });
    reveals.forEach(function (el) { io.observe(el); });
  } else { reveals.forEach(function (el) { el.classList.add('in'); }); }

  /* ---------- count-up ---------- */
  function fmt(n) { return Math.round(n).toLocaleString('en-US'); }
  var counters = [].slice.call(document.querySelectorAll('[data-count]'));
  function runCount(el) {
    var target = parseFloat(el.getAttribute('data-count'));
    var suffix = el.getAttribute('data-suffix') || '';
    var t0 = null, dur = 1200;
    function step(ts) {
      if (t0 === null) t0 = ts;
      var k = Math.min((ts - t0) / dur, 1), eased = 1 - Math.pow(1 - k, 3);
      el.textContent = fmt(target * eased) + suffix;
      if (k < 1) requestAnimationFrame(step); else el.textContent = fmt(target) + suffix;
    }
    requestAnimationFrame(step);
    /* safety net: always end on the exact value, even if the tab was in the background */
    setTimeout(function () { el.textContent = fmt(target) + suffix; }, dur + 400);
  }
  if ('IntersectionObserver' in window) {
    var co = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { runCount(e.target); co.unobserve(e.target); } });
    }, { threshold: 0.5 });
    counters.forEach(function (el) { co.observe(el); });
  } else { counters.forEach(function (el) { el.textContent = fmt(parseFloat(el.getAttribute('data-count'))) + (el.getAttribute('data-suffix') || ''); }); }

  /* ---------- bar charts: <div class="bars" data-title data-sub data-scale data-rows='[["label", value, "text", "bad"]]'> ---------- */
  [].slice.call(document.querySelectorAll('.bars')).forEach(function (box) {
    var rows = JSON.parse(box.getAttribute('data-rows'));
    var scale = box.getAttribute('data-scale') || 'linear';
    var max = Math.max.apply(null, rows.map(function (r) { return r[1]; }));
    function w(v) {
      if (scale === 'log') { return Math.max(2, 100 * Math.log10(v + 1) / Math.log10(max + 1)); }
      return Math.max(1.2, 100 * v / max);
    }
    var html = '<div class="chart"><h4>' + (box.getAttribute('data-title') || '') + '</h4><div class="sub">' + (box.getAttribute('data-sub') || '') + '</div>';
    rows.forEach(function (r) {
      var pw = w(r[1]);
      var pos = pw > 76 ? 'left:auto;right:10px;color:#fff;text-shadow:none;' : 'left:calc(' + pw.toFixed(2) + '% + 8px);';
      html += '<div class="bar-row"><div class="name">' + r[0] + '</div><div class="bar-track"><div class="bar-fill ' + (r[3] || '') + '" data-w="' + pw.toFixed(2) + '"></div><div class="bar-val" style="' + pos + '">' + (r[2] || fmt(r[1])) + '</div></div></div>';
    });
    box.innerHTML = html + '</div>';
    var fills = [].slice.call(box.querySelectorAll('.bar-fill'));
    function grow() { fills.forEach(function (f) { f.style.width = f.getAttribute('data-w') + '%'; }); }
    if ('IntersectionObserver' in window) {
      var bo = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting) { grow(); bo.unobserve(e.target); } });
      }, { threshold: 0.3 });
      bo.observe(box);
    } else { grow(); }
  });

  /* ---------- lightbox ---------- */
  var lb = document.createElement('div');
  lb.className = 'lightbox';
  lb.innerHTML = '<img alt="">';
  document.body.appendChild(lb);
  lb.addEventListener('click', function () { lb.classList.remove('open'); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') lb.classList.remove('open'); });
  [].slice.call(document.querySelectorAll('.fig img')).forEach(function (img) {
    img.addEventListener('click', function () { lb.querySelector('img').src = img.src; lb.querySelector('img').alt = img.alt; lb.classList.add('open'); });
  });

  /* ---------- toggles: <div class="toggle" data-target="id"><button data-p="a">..</button></div> + <div id="id"><div class="panel" data-p="a"> ---------- */
  [].slice.call(document.querySelectorAll('.toggle')).forEach(function (tg) {
    var target = document.getElementById(tg.getAttribute('data-target'));
    if (!target) return;
    var buttons = [].slice.call(tg.querySelectorAll('button'));
    function show(key) {
      buttons.forEach(function (b) { b.classList.toggle('on', b.getAttribute('data-p') === key); });
      [].slice.call(target.querySelectorAll('.panel')).forEach(function (p) { p.classList.toggle('on', p.getAttribute('data-p') === key); });
    }
    buttons.forEach(function (b) { b.addEventListener('click', function () { show(b.getAttribute('data-p')); }); });
    show(buttons[0].getAttribute('data-p'));
  });
})();

/* Reyes Sitework — MeshCentral futuristic theme helper.
   Marks the page for CSS scoping and sets the login wordmark. */
(function () {
    'use strict';
    function boot() {
        if (document.documentElement) { document.documentElement.classList.add('mc-cyber'); }
        if (document.body) { document.body.classList.add('reyes'); }
        var picture = document.getElementById('loginPicture');
        if (picture && !picture.getAttribute('src')) {
            picture.src = 'images/reyes-title.png';
            picture.alt = 'Reyes Sitework';
        }
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }
})();

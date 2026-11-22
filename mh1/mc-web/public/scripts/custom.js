/* Reyes Sitework — MeshCentral brand helper.
   Adds the wordmark to the login card and marks the page for CSS scoping. */
(function () {
    function boot() {
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

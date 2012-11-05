
$(function() {
  if($('#logArea')) {
    var area = $('#logArea');
    var toggle = $('#logToggler');

    var origH = area.css('height');
    toggle.html('(maximize)');
    toggle.click( function() {
      var h = area.css('height');
      if(h == origH) {
        area.css('height', 'auto');
      } else {
        area.css('height', origH);
      }
      return false;
    });
  }
});

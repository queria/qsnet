
$(document).ready( function () {
  $('#macNotes .inner').css('height', (
    Math.min($(window).height() - 220, $('article').height() - 100))+'px');
  $('.mac').mouseenter( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').addClass('macOver');
  });
  $('.mac').mouseleave( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').removeClass('macOver');
  });
});


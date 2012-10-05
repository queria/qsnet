
$(document).ready( function () {
  $('#macNotes .inner').css('height', ($(window).height() - 220)+'px');
  $('.mac').mouseenter( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').addClass('macOver');
  });
  $('.mac').mouseleave( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').removeClass('macOver');
  });
});


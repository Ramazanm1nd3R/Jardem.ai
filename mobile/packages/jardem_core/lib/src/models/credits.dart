/// Attribution of a bundled photo (see `assets/images/ATTRIBUTION.md`).
class PhotoCredit {
  const PhotoCredit(this.file, this.subject, this.author, this.license, this.source);

  final String file;
  final String subject;
  final String author;
  final String license;
  final String source;
}

/// All photos are from Wikimedia Commons, resized and re-encoded.
const List<PhotoCredit> kPhotoCredits = [
  PhotoCredit(
    'almaty_skyline_1',
    'Панорама Алматы',
    'Kalpak Travel (Flickr)',
    'CC BY 2.0',
    'https://commons.wikimedia.org/wiki/File:Kazakhstan,_Almaty_view.jpg',
  ),
  PhotoCredit(
    'ambulance_kz_1',
    'Скорая помощь 103, Боралдай',
    'Nikolai Bulykin',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Боралдай,_скорая_помощь_на_Аэродромной_98.jpg',
  ),
  PhotoCredit(
    'ambulance_kz_2',
    'Скорая помощь на Толе би, Алматы',
    'Nikolai Bulykin',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Алматы,_скорая_на_Толе_би-Жумалиева_(2).jpg',
  ),
  PhotoCredit(
    'ambulance_kz_reanimation',
    'Реанимационный автомобиль',
    'Аппарат Правления',
    'CC0 1.0',
    'https://commons.wikimedia.org/wiki/File:Реанимационный_автомобиль.jpg',
  ),
  PhotoCredit(
    'police_kz_1',
    'Полицейский Chevrolet Equinox, Алматы',
    'Nikolai Bulykin',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Алматы,_полицейский_Chevrolet_Equinox_на_площади_Абая.jpg',
  ),
  PhotoCredit(
    'police_kz_2',
    'Патрульный автомобиль, Алматы',
    'Nurken',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Police_car_near_the_later-to-be-postponed_Ye_concert_in_Almaty,_14_August_2026.jpg',
  ),
  PhotoCredit(
    'fire_kz_1',
    'Пожарный Iveco Magirus, Ават',
    'Nikolai Bulykin',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Ават,_пожарный_Iveco.jpg',
  ),
  PhotoCredit(
    'fire_kz_2',
    'Пожарный ЗИЛ, Астана',
    'Peretz Partensky (Flickr)',
    'CC BY-SA 2.0',
    'https://commons.wikimedia.org/wiki/File:Astana_Firetruck_(4054861283).jpg',
  ),
  PhotoCredit(
    'rescue_kz_1',
    'УАЗ Patriot спасателей, Медеу',
    'Nikolai Bulykin',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Медео,_УАЗ_Patriot_на_плотине.jpg',
  ),
];

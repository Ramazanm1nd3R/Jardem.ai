import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:jardem_responder/logic/closures.dart';

void main() {
  const a = RoadClosure(id: 'cl-1', lat: 43.2, lon: 76.9, reason: 'ДТП');
  const b = RoadClosure(id: 'cl-2', lat: 43.2, lon: 76.9, reason: '  ');

  test('reasons and lifetime', () {
    expect(kClosureReasons, ['ДТП', 'Ремонт', 'Затор', 'Другое']);
    expect(kClosureMinutes, 30);
  });

  test('title', () {
    expect(closureTitle(a), 'ДТП');
    expect(closureTitle(b), 'Перекрытие');
    expect(closureTitle(const RoadClosure(id: 'x', lat: 0, lon: 0, reason: ' Ремонт ')), 'Ремонт');
  });

  test('only own closures can be lifted', () {
    expect(canLift(a, {'cl-1'}), isTrue);
    expect(canLift(b, {'cl-1'}), isFalse);
    expect(canLift(a, const {}), isFalse);
  });

  test('add / remove return new sets', () {
    final mine = {'cl-1'};
    expect(withClosure(mine, 'cl-2'), {'cl-1', 'cl-2'});
    expect(withClosure(mine, 'cl-1'), {'cl-1'});
    expect(withClosure(mine, ''), {'cl-1'});
    expect(withoutClosure({'cl-1', 'cl-2'}, 'cl-1'), {'cl-2'});
    expect(withoutClosure(mine, 'nope'), {'cl-1'});
    expect(mine, {'cl-1'});
  });

  test('prune forgets closures that are gone', () {
    expect(pruneClosures({'cl-1', 'cl-9'}, const [a, b]), {'cl-1'});
    expect(pruneClosures({'cl-1'}, const []), isEmpty);
    expect(pruneClosures(const {}, const [a]), isEmpty);
  });
}

import 'package:drowzydiary/prototype/prototype_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const good = '{"emotion":"sadness","domains":["work","sleep_substances"],"summary":"Lelah karena kerja."}';

  test('strict JSON matching the schema', () {
    final c = checkJsonOutput(good);
    expect([c.strict, c.lenient, c.schema], [true, true, true]);
  });

  test('JSON wrapped in markdown is lenient only', () {
    final c = checkJsonOutput('```json\n$good\n```');
    expect([c.strict, c.lenient, c.schema], [false, true, true]);
  });

  test('valid JSON with an unknown domain fails the schema', () {
    final c = checkJsonOutput('{"emotion":"joy","domains":["food"],"summary":"x"}');
    expect([c.strict, c.schema, c.error], [true, false, 'bad domains']);
  });

  test('non-JSON fails', () {
    expect(checkJsonOutput('Maaf, saya tidak bisa.').lenient, isFalse);
  });
}

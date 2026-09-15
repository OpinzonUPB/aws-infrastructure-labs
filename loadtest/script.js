// Script de prueba de carga para k6.
//
// No define usuarios (VUs) ni duración aquí: esos valores se pasan desde
// scripts/load_test.sh con las opciones --vus y --duration, para que
// todo el "qué se está probando" quede visible en la línea de comandos.
//
// La URL a golpear llega por la variable de entorno BASE_URL, por ejemplo:
//   BASE_URL=http://localhost:8000/compute

import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000/compute';

export default function () {
  const res = http.get(BASE_URL);
  check(res, {
    'status es 200': (r) => r.status === 200,
  });
}

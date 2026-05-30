import '../core/constants.dart';
import '../models/legal_terms.dart';

class LegalService {
  const LegalService();

  LegalTerms get currentTerms => LegalTerms(
        version: AppConstants.termsVersion,
        title: 'Terminos y condiciones de uso — TURNO SpA',
        bullets: const [
          'TURNO es una plataforma de intermediacion tecnologica para carpooling universitario.',
          'El servicio se limita a conectar estudiantes que comparten gastos de traslado.',
          'Los conductores declaran que los traslados no tienen fines de lucro.',
          'Uso restringido a miembros de comunidades universitarias vigentes.',
          'Comision fija de \$190 CLP por transaccion para mantenimiento de la plataforma.',
          'TURNO no se responsabiliza por accidentes, conducta o fallas tecnicas.',
          'Cancelaciones tardias e inasistencias generan cargos segun politica interna.',
          'El conductor tiene un margen de espera de 15 minutos.',
          'Datos personales tratados conforme a Ley 19.628 de Chile.',
          'Jurisdiccion: Tribunales Ordinarios de Santiago, Chile.',
        ],
        sections: const [
          LegalTermsSection(
            title: '1. NATURALEZA DEL SERVICIO: INTERMEDIACION TECNOLOGICA',
            body: 'Turno SpA (en adelante, "TURNO") es una plataforma tecnologica que actua exclusivamente como un punto de encuentro entre particulares (estudiantes universitarios) para la organizacion de traslados compartidos bajo la modalidad de carpooling (gastos compartidos).\n\n'
                'TURNO no es una empresa de transportes, no es duena de vehiculos, no emplea conductores ni presta servicios de transporte remunerado de pasajeros. El servicio se limita a proveer el software para que los usuarios coordinen sus rutas y dividan los costos operativos del viaje (combustible, peajes y mantenimiento).',
          ),
          LegalTermsSection(
            title: '2. DECLARACION DE CARPOOLING Y AUSENCIA DE LUCRO',
            body: 'Al aceptar estos terminos, el Usuario Conductor declara y acepta que:\n\n'
                '• El traslado no tiene fines de lucro ni constituye una actividad profesional remunerada.\n\n'
                '• El monto recibido a traves de la plataforma representa una contribucion a los gastos del viaje y no una tarifa por servicio de transporte.\n\n'
                '• El Conductor se dirige al mismo destino (o cercanias) que el Pasajero por motivos personales o academicos, independientemente de la existencia del viaje coordinado en la App.',
          ),
          LegalTermsSection(
            title: '3. REGISTRO Y COMUNIDAD UNIVERSITARIA',
            body: 'El uso de la App esta restringido a miembros de comunidades universitarias vigentes. TURNO se reserva el derecho de solicitar documentos que acrediten la condicion de estudiante o colaborador de las instituciones vinculadas.\n\n'
                'El Usuario es el unico responsable de la veracidad de la informacion registrada (RUT, Licencia de conducir, Permiso de circulacion y Seguro Obligatorio - SOAP).',
          ),
          LegalTermsSection(
            title: '4. BILLETERA VIRTUAL Y PAGOS',
            body: 'Recargas: Los Usuarios podran cargar saldo en su Billetera Virtual mediante los metodos de pago habilitados.\n\n'
                'Comisiones: TURNO cobrara una comision fija por transaccion de \$190 CLP por el uso y mantenimiento de la plataforma. Esta comision se descuenta del monto transaccionado entre particulares.\n\n'
                'Retiros: El Usuario Conductor podra solicitar el retiro de sus fondos acumulados hacia su cuenta bancaria personal, sujeto a los tiempos de procesamiento de la pasarela de pagos.\n\n'
                'Garantia de Pago: Una vez confirmada la reserva por ambas partes, el monto del viaje queda retenido para asegurar el pago al Conductor, evitando la informalidad de los cobros manuales.',
          ),
          LegalTermsSection(
            title: '5. LIMITACION DE RESPONSABILIDAD Y SEGUROS',
            body: 'Accidentes: TURNO no se hace responsable por danos materiales, lesiones personales o fallecimiento derivados de accidentes de transito durante los trayectos. La responsabilidad civil y penal recae exclusivamente en los conductores y pasajeros involucrados, quienes deben contar con sus seguros obligatorios (SOAP) y opcionales al dia.\n\n'
                'Conducta: TURNO no se responsabiliza por el comportamiento de los usuarios dentro del vehiculo. Sin embargo, se reserva el derecho de expulsar permanentemente a cualquier usuario que infrinja las normas de respeto, puntualidad o seguridad.\n\n'
                'Fallas Tecnicas: TURNO no garantiza el funcionamiento ininterrumpido de la App ni se hace responsable por perdidas economicas derivadas de fallas en el servidor o en la integracion con mapas de terceros (Google Maps/Apple Maps).',
          ),
          LegalTermsSection(
            title: '6. CANCELACIONES Y PUNTUALIDAD',
            body: 'Para mantener la eficiencia de la plataforma y evitar el desorden de los grupos de chat:\n\n'
                '• Se aplicaran cargos por cancelacion tardia o inasistencia ("No-show") segun la politica vigente dentro de la App.\n\n'
                '• El Conductor tiene un margen de espera de 15 minutos, tras los cuales podra dar por cancelado el viaje sin derecho a devolucion para el Pasajero.\n\n'
                '• Cancelar a ultima hora (menos de 2 horas antes de la salida) genera un strike al conductor.\n\n'
                '• Con 2 strikes activos, el conductor y su vehiculo quedan suspendidos por 2 meses.',
          ),
          LegalTermsSection(
            title: '7. PRIVACIDAD Y DATOS PERSONALES',
            body: 'TURNO utiliza la ubicacion en tiempo real de los usuarios para facilitar el encuentro en los puntos de abordaje definidos. Al usar la App, el usuario consiente el tratamiento de sus datos de geolocalizacion y contacto conforme a la Ley N° 19.628 sobre Proteccion de la Vida Privada.',
          ),
          LegalTermsSection(
            title: '8. PROPIEDAD INTELECTUAL',
            body: 'El diseno de la interfaz, el logotipo de TURNO, los sonidos icónicos de notificacion y el codigo fuente son propiedad exclusiva de Turno SpA. Queda prohibida cualquier reproduccion o ingenieria inversa de la plataforma.',
          ),
          LegalTermsSection(
            title: '9. LEY APLICABLE Y JURISDICCION',
            body: 'Cualquier controversia derivada del uso de la plataforma sera resuelta bajo las leyes de la Republica de Chile, sometiendose las partes a la jurisdiccion de los Tribunales Ordinarios de Justicia de la comuna de Santiago.',
          ),
        ],
      );
}

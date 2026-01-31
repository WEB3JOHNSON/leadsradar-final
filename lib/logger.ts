export interface LogContext {
    [key: string]: any;
}

class Logger {
    info(message: string, context?: LogContext) {
        this.log('INFO', message, context);
    }

    warn(message: string, context?: LogContext) {
        this.log('WARN', message, context);
    }

    error(message: string, context?: LogContext, error?: any) {
        this.log('ERROR', message, {
            ...context,
            error_message: error?.message,
            error_stack: error?.stack
        });
    }

    private log(level: 'INFO' | 'WARN' | 'ERROR', message: string, context?: LogContext) {
        const entry = {
            timestamp: new Date().toISOString(),
            level,
            message,
            ...context
        };

        // In production, this would go to Axiom/Datadog/Logtail
        console.log(JSON.stringify(entry));
    }
}

export const logger = new Logger();

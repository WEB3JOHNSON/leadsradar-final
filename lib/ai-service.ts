import { GoogleGenerativeAI } from '@google/generative-ai';
import { AI_CONFIG, APP_CONFIG } from './constants';
import { logger } from './logger';

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
const model = genAI.getGenerativeModel({ model: AI_CONFIG.model });

export interface GeneratePitchParams {
    leadName?: string;
    tweetText: string;
    tweetUrl?: string; // Optional context
    userBio?: string; // The user's bio/service description
    tone?: 'professional' | 'casual' | 'friendly' | 'urgent';
}

export async function generatePitch(params: GeneratePitchParams): Promise<string> {
    const { leadName = 'there', tweetText, userBio, tone = 'professional' } = params;

    // Construct the prompt
    // We use a structured prompt to ensure quality
    const prompt = `
    You are an expert sales copywriter assistant for "${APP_CONFIG.name}".
    Your goal is to write a personalized Twitter DM pitch.
    
    CONTEXT:
    - User's Service/Bio: "${userBio || 'I help businesses grow.'}"
    - Lead's Tweet: "${tweetText}"
    - Goal: Start a conversation to offer the user's service.
    
    INSTRUCTIONS:
    - Tone: ${tone}.
    - Length: Keep it under 280 characters if possible, or max 2 brief sentences.
    - Personalization: Reference their tweet specifically.
    - Call to Action: Low friction question.
    - Formatting: Plain text, no hashtags, no emojis (unless tone is friendly).
    
    DRAFT THE DM:
  `;

    try {
        const result = await model.generateContent(prompt);
        const response = await result.response;
        const text = response.text();

        return text.trim();
    } catch (error: any) {
        logger.error('Gemini API Error', { params }, error);
        throw new Error('Failed to generate pitch via Gemini');
    }
}

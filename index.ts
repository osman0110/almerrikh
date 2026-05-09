import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

export const generateWeeklyPlan = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }

  const uid = context.auth.uid;
  const { trainingPath } = data;

  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User profile not found.");
  }

  const userData = userDoc.data()!;

  // Mocking AI API call. In production, securely call OpenAI or Gemini here.
  // Example: const response = await fetch('AI_API_URL', { headers: { Authorization: `Bearer ${functions.config().ai.key}` }... });
  const aiPlanMock = {
    weekNumber: 1,
    focus: `Foundations for ${trainingPath.replace('_', ' ')}`,
    difficulty: "beginner",
    days: [
      {
        dayName: "Day 1",
        sessionType: trainingPath,
        durationMinutes: userData.preferredTrainingDuration || 30,
        title: "Control and Movement",
        warmup: [
          { name: "Dynamic Stretching", durationMinutes: 5 }
        ],
        drills: [
          {
            id: "hand-reaction",
            name: "Hand Reaction",
            category: "reaction",
            sets: 3,
            durationMinutes: 10,
            restSeconds: 30,
            cameraFeedback: true,
            targetMetrics: ["speed", "accuracy"]
          },
          {
            id: "get-in-box",
            name: "Sprint Cube",
            category: "fitness",
            sets: 2,
            durationMinutes: 10,
            restSeconds: 60,
            cameraFeedback: true,
            targetMetrics: ["agility", "balance"]
          }
        ],
        cooldown: [
          { name: "Static Stretching", durationMinutes: 5 }
        ]
      }
    ]
  };

  try {
    const planData = {
      ...aiPlanMock,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      generatedByAI: true,
      status: "active"
    };

    const planRef = await userRef.collection("plans").add(planData);
    return { success: true, planId: planRef.id };
  } catch (error) {
    console.error("Plan Generation Error:", error);
    throw new functions.https.HttpsError("internal", "Failed to save generated plan.");
  }
});

export const adjustNextWeekPlan = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  // Place logic here to read sessions, calculate scores, and query AI for an adjusted plan
  return { success: true, message: "Adjusted plan generated." };
});

export const submitSessionResult = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");

  const uid = context.auth.uid;
  const { planId, drillId, accuracy, speed, agility, balance, calories, reps, durationMinutes } = data;

  const performanceScore = (accuracy * 0.4) + (speed * 0.3) + (agility * 0.2) + (balance * 0.1);

  const sessionData = {
    planId, drillId, accuracy, speed, agility, balance, calories, reps, durationMinutes, performanceScore,
    date: admin.firestore.FieldValue.serverTimestamp(),
    feedback: performanceScore > 80 ? "Excellent form!" : "Focus on technique next time."
  };

  const userRef = db.collection("users").doc(uid);
  await userRef.collection("sessions").add(sessionData);

  const earnedXp = Math.round(performanceScore * 2);
  await userRef.update({
    xp: admin.firestore.FieldValue.increment(earnedXp),
    streak: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  return { success: true, earnedXp, leveledUp: false };
});